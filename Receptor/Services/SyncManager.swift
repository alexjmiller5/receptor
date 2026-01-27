import Foundation
import SwiftData
import Network
#if os(iOS)
import BackgroundTasks
#endif
import UserNotifications

@MainActor
final class SyncManager: ObservableObject {
    static let shared = SyncManager()

    static let backgroundTaskIdentifier = "com.alexmiller.receptor.sync"
    static let backgroundSessionIdentifier = "com.alexmiller.receptor.background-wake"

    @Published private(set) var isOnline = false
    @Published private(set) var isSyncing = false
    @Published private(set) var syncLog: [SyncLogEntry] = []

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "NetworkMonitor")
    private let maxLogEntries = 50

    private var currentFlushTask: Task<Int, Never>?
    private var backgroundWakeInFlight = false

    private(set) var modelContainer: ModelContainer?

    /// Stored by AppDelegate when the OS delivers a background session event.
    /// Called by BackgroundSessionDelegate when the session finishes.
    var backgroundSessionCompletionHandler: (() -> Void)?

    /// Lazy-init background URLSession. Reconnecting after relaunch picks up in-flight tasks.
    private lazy var backgroundSession: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: Self.backgroundSessionIdentifier)
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        return URLSession(configuration: config, delegate: backgroundSessionDelegate, delegateQueue: nil)
    }()

    private let backgroundSessionDelegate = BackgroundSessionDelegate()

    private init() {
        setupNetworkMonitoring()
        loadSyncLog()
    }

    // MARK: - Setup

    func configure(with container: ModelContainer) {
        self.modelContainer = container
    }

    /// Re-creates the background URLSession so the OS can deliver queued callbacks after relaunch.
    func reconnectBackgroundSession() {
        _ = backgroundSession
    }

    private func setupNetworkMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                let wasOffline = self?.isOnline == false
                self?.isOnline = path.status == .satisfied
                if path.status == .satisfied && wasOffline {
                    self?.addLogEntry("Network restored, triggering flush", trigger: .networkRestored)
                    self?.requestFlush(trigger: .networkRestored)
                }
            }
        }
        monitor.start(queue: monitorQueue)
    }

    // MARK: - Queue Operations

    /// Saves a thought to the database and fires off a queue flush (non-blocking).
    /// CaptureThoughtIntent calls this and returns "Queued" immediately.
    func queueThought(_ text: String, trigger: SyncTrigger = .captureIntent) async {
        guard let container = modelContainer else { return }

        let context = container.mainContext
        let thought = Thought(text: text)
        context.insert(thought)
        saveContextWithErrorHandling(context)

        addLogEntry("Queued: \(text.prefix(30))...", trigger: trigger)

        // Fire and forget - don't await so callers return immediately
        requestFlush(trigger: trigger)
    }

    /// Cancels any in-progress flush and starts a new one from the top of the queue.
    /// Intent triggers route through background wake; all others flush directly.
    @discardableResult
    func requestFlush(trigger: SyncTrigger) -> Task<Int, Never> {
        currentFlushTask?.cancel()

        if trigger == .captureIntent || trigger == .flushIntent {
            // Intent path: fire a background URLSession ping so the OS wakes us
            performBackgroundWake(trigger: trigger)
            // Return a task that resolves immediately — the real flush happens on wake
            let task = Task { 0 }
            currentFlushTask = task
            return task
        }

        let task = Task {
            await performFlush(trigger: trigger)
        }
        currentFlushTask = task
        return task
    }

    // MARK: - Background Wake

    /// Fires a no-op GET to captive.apple.com via Background URLSession.
    /// When the OS completes it, the app wakes and runs a foreground FIFO flush.
    private func performBackgroundWake(trigger: SyncTrigger) {
        guard !backgroundWakeInFlight else {
            addLogEntry("Background wake already in flight, skipping", trigger: trigger)
            return
        }
        backgroundWakeInFlight = true
        addLogEntry("Firing background wake ping", trigger: trigger)

        let url = URL(string: "https://captive.apple.com")!
        let request = URLRequest(url: url)
        backgroundSession.dataTask(with: request).resume()
    }

    /// Called by BackgroundSessionDelegate when the ping completes.
    func handleBackgroundWakeCompleted() {
        backgroundWakeInFlight = false
        addLogEntry("Background wake completed, starting FIFO flush", trigger: .backgroundWake)
        requestFlush(trigger: .backgroundWake)
    }

    /// The actual flush implementation. Processes the queue in strict FIFO order.
    /// Checks for cancellation between each thought (a newer flush may have been requested).
    private func performFlush(trigger: SyncTrigger) async -> Int {
        guard isOnline else {
            addLogEntry("Flush skipped: offline", trigger: trigger)
            return 0
        }
        guard let container = modelContainer else { return 0 }

        isSyncing = true
        defer { isSyncing = false }

        let context = container.mainContext

        let descriptor = FetchDescriptor<Thought>(sortBy: [SortDescriptor(\.createdAt)])
        guard let allThoughts = try? context.fetch(descriptor) else { return 0 }

        let thoughts = allThoughts.filter {
            $0.status == .queued || $0.status == .failed
        }

        if thoughts.isEmpty {
            addLogEntry("Flush: queue empty", trigger: trigger)
            return 0
        }

        addLogEntry("Flush: \(thoughts.count) queued", trigger: trigger)

        var successCount = 0
        for thought in thoughts {
            // A newer flush was requested - stop this one, it will restart from the top
            if Task.isCancelled {
                addLogEntry("Flush restarted by newer trigger", trigger: trigger)
                return successCount
            }

            let success = await receptThought(thought, trigger: trigger)
            if success {
                successCount += 1
            } else {
                break
            }
        }

        // One batch notification at the end (not per-thought)
        if successCount > 0 && trigger != .captureIntent {
            await sendNotification(count: successCount, trigger: trigger)
        }

        return successCount
    }

    // MARK: - Upload

    /// Sends a single thought to the processor. Blocking - waits for the response.
    private func receptThought(_ thought: Thought, trigger: SyncTrigger) async -> Bool {
        guard let apiKey = Configuration.apiKey,
              let baseURL = Configuration.intakerURL else {
            addLogEntry("Upload failed: not configured", trigger: trigger)
            return false
        }

        var urlComponents = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        urlComponents.queryItems = [URLQueryItem(name: "key", value: apiKey)]

        var request = URLRequest(url: urlComponents.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = ["raw_text": thought.text]
        request.httpBody = try? JSONEncoder().encode(payload)

        thought.status = .sending
        saveContextWithErrorHandling(modelContainer?.mainContext)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                thought.status = .failed
                thought.retryCount += 1
                thought.lastError = "Server error: \((response as? HTTPURLResponse)?.statusCode ?? 0)"
                saveContextWithErrorHandling(modelContainer?.mainContext)
                addLogEntry("Upload failed: server error", trigger: trigger)
                return false
            }

            thought.status = .sent
            thought.sentAt = Date()
            thought.sentVia = trigger
            thought.lastError = nil
            saveContextWithErrorHandling(modelContainer?.mainContext)
            addLogEntry("Sent: \(thought.text.prefix(20))...", trigger: trigger)
            return true
        } catch {
            thought.status = .failed
            thought.retryCount += 1
            thought.lastError = error.localizedDescription
            saveContextWithErrorHandling(modelContainer?.mainContext)
            addLogEntry("Upload failed: \(error.localizedDescription)", trigger: trigger)
            return false
        }
    }

    // MARK: - DB Save with Error Handling

    private func saveContextWithErrorHandling(_ context: ModelContext?) {
        guard let context else { return }
        do {
            try context.save()
        } catch {
            addLogEntry("DB save failed: \(error.localizedDescription)", trigger: .appBecameActive)
            Task {
                await sendNotification(title: "Receptor - DB Error", body: "Failed to save: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Sync Log

    private var syncLogURL: URL? {
        Configuration.sharedContainerURL?.appendingPathComponent("syncLog.json")
    }

    private func addLogEntry(_ message: String, trigger: SyncTrigger) {
        let entry = SyncLogEntry(timestamp: Date(), message: message, trigger: trigger)
        syncLog.insert(entry, at: 0)
        if syncLog.count > maxLogEntries {
            syncLog = Array(syncLog.prefix(maxLogEntries))
        }
        saveSyncLog()
    }

    private func saveSyncLog() {
        guard let url = syncLogURL else { return }
        try? JSONEncoder().encode(syncLog).write(to: url)
    }

    private func loadSyncLog() {
        guard let url = syncLogURL,
              let data = try? Data(contentsOf: url),
              let log = try? JSONDecoder().decode([SyncLogEntry].self, from: data) else {
            return
        }
        syncLog = log
    }

    func clearSyncLog() {
        syncLog = []
        saveSyncLog()
    }

    // MARK: - Notifications

    static func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    private func sendNotification(count: Int, trigger: SyncTrigger) async {
        await sendNotification(
            title: "Receptor",
            body: "Synced \(count) thought\(count == 1 ? "" : "s") via \(trigger.rawValue)"
        )
    }

    private func sendNotification(title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        try? await UNUserNotificationCenter.current().add(request)
        addLogEntry("Notification: \(body)", trigger: .appBecameActive)
    }

    // MARK: - Background Tasks (iOS only)

    #if os(iOS)
    static func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: backgroundTaskIdentifier,
            using: nil
        ) { task in
            Task { @MainActor in
                await handleBackgroundTask(task as! BGProcessingTask)
            }
        }
    }

    static func scheduleBackgroundSync() {
        let request = BGProcessingTaskRequest(identifier: backgroundTaskIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        try? BGTaskScheduler.shared.submit(request)
    }

    @MainActor
    private static func handleBackgroundTask(_ task: BGProcessingTask) async {
        scheduleBackgroundSync() // Schedule next occurrence

        SyncManager.shared.addLogEntry("Background task started", trigger: .backgroundTask)

        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }

        let count = await SyncManager.shared.requestFlush(trigger: .backgroundTask).value
        task.setTaskCompleted(success: count >= 0)
    }
    #endif
}

// MARK: - Background URLSession Delegate

/// Handles completion of the background wake ping. Must be a separate non-MainActor class
/// because URLSessionDelegate callbacks are called on the delegate queue.
final class BackgroundSessionDelegate: NSObject, URLSessionDataDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        Task { @MainActor in
            SyncManager.shared.handleBackgroundWakeCompleted()

            // Call the completion handler stored by AppDelegate so the OS knows we're done
            SyncManager.shared.backgroundSessionCompletionHandler?()
            SyncManager.shared.backgroundSessionCompletionHandler = nil
        }
    }
}

// MARK: - Supporting Types

struct SyncLogEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let message: String
    let trigger: SyncTrigger

    init(timestamp: Date, message: String, trigger: SyncTrigger) {
        self.id = UUID()
        self.timestamp = timestamp
        self.message = message
        self.trigger = trigger
    }
}

enum SyncError: LocalizedError {
    case missingConfiguration
    case serverError(Int)

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return "API key or URL not configured"
        case .serverError(let code):
            return "Server returned error: \(code)"
        }
    }
}
