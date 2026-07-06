import Foundation
import SwiftData
import Network
import os.log
#if os(iOS)
import BackgroundTasks
#endif
import UserNotifications

// MARK: - OSLog Instances

private let subsystem = "com.alexmiller.receptor"

private let syncLog_os    = OSLog(subsystem: subsystem, category: "Sync")
private let uploadLog     = OSLog(subsystem: subsystem, category: "Upload")
private let flushLog      = OSLog(subsystem: subsystem, category: "Flush")
private let httpLog       = OSLog(subsystem: subsystem, category: "HTTP")
private let delegateLog   = OSLog(subsystem: subsystem, category: "Delegate")
private let exportLog     = OSLog(subsystem: subsystem, category: "Export")

/// Returns "pid=X proc=Y" for identifying which process is running.
private func processTag() -> String {
    let pid = ProcessInfo.processInfo.processIdentifier
    let proc = ProcessInfo.processInfo.processName
    return "pid=\(pid) proc=\(proc)"
}

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
    private let lockDuration: TimeInterval = 10.0

    private(set) var modelContainer: ModelContainer?

    /// Stored by AppDelegate when the OS delivers a background session event.
    /// Called when all background session tasks finish.
    var backgroundSessionCompletionHandler: (() -> Void)?

    // MARK: - Upload File Helpers

    /// Directory for temporary upload payload files.
    static var uploadsDirectory: URL? {
        guard let container = Configuration.sharedContainerURL else { return nil }
        let dir = container.appendingPathComponent("uploads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// File URL for a specific thought's upload payload.
    static func uploadFileURL(for thoughtId: UUID) -> URL? {
        uploadsDirectory?.appendingPathComponent("\(thoughtId.uuidString).json")
    }

    /// Lazy-init background URLSession. Reconnecting after relaunch picks up in-flight tasks.
    private lazy var backgroundSession: URLSession = {
        os_log("[SYNC] backgroundSession lazy init — creating session %{public}@ | %{public}@", log: syncLog_os, type: .default, Self.backgroundSessionIdentifier, processTag())
        let config = URLSessionConfiguration.background(withIdentifier: Self.backgroundSessionIdentifier)
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.waitsForConnectivity = true
        os_log("[SYNC] backgroundSession config: discretionary=%{public}d, launchEvents=%{public}d, waitsForConnectivity=%{public}d", log: syncLog_os, type: .default, config.isDiscretionary ? 1 : 0, config.sessionSendsLaunchEvents ? 1 : 0, config.waitsForConnectivity ? 1 : 0)
        return URLSession(configuration: config, delegate: backgroundSessionDelegate, delegateQueue: nil)
    }()

    private let backgroundSessionDelegate = BackgroundSessionDelegate()

    private init() {
        os_log("[SYNC] SyncManager.init() | %{public}@", log: syncLog_os, type: .default, processTag())
        setupNetworkMonitoring()
    }

    // MARK: - Setup

    func configure(with container: ModelContainer) {
        os_log("[SYNC] configure(with:) — setting modelContainer | %{public}@", log: syncLog_os, type: .default, processTag())
        self.modelContainer = container
        loadSyncLog()
        os_log("[SYNC] configure(with:) — done, syncLog count=%d", log: syncLog_os, type: .default, syncLog.count)
    }

    /// Re-creates the background URLSession so the OS can deliver queued callbacks after relaunch.
    func reconnectBackgroundSession() {
        os_log("[SYNC] reconnectBackgroundSession() — touching session | %{public}@", log: syncLog_os, type: .default, processTag())
        DebugFileLog.write("[SYNC] reconnectBackgroundSession()")
        _ = backgroundSession
        os_log("[SYNC] reconnectBackgroundSession() — done", log: syncLog_os, type: .default)
    }

    private func setupNetworkMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                let wasOffline = self?.isOnline == false
                self?.isOnline = path.status == .satisfied
                if path.status == .satisfied && wasOffline {
                    os_log("[SYNC] Network restored, triggering flush | %{public}@", log: syncLog_os, type: .default, processTag())
                    self?.addLogEntry("Network restored, triggering flush", trigger: .networkRestored)
                    self?.requestFlush(trigger: .networkRestored)
                }
            }
        }
        monitor.start(queue: monitorQueue)
    }

    // MARK: - Queue Operations

    /// Saves a thought to the database and fires off a queue flush.
    /// CaptureThoughtIntent calls this and returns "Queued" immediately.
    func queueThought(_ text: String, trigger: SyncTrigger = .captureIntent) async {
        os_log("[SYNC] queueThought() — text='%{public}@' trigger=%{public}@ | %{public}@", log: syncLog_os, type: .default, String(text.prefix(30)), trigger.rawValue, processTag())

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            os_log("[SYNC] queueThought() — SKIP: empty text", log: syncLog_os, type: .error)
            addLogEntry("QUEUE-SKIP empty text", trigger: trigger)
            return
        }

        guard let container = modelContainer else {
            os_log("[SYNC] queueThought() — ABORT: modelContainer is nil", log: syncLog_os, type: .error)
            return
        }

        let context = container.mainContext
        let thought = Thought(text: text)
        context.insert(thought)
        saveContextWithErrorHandling(context)

        let thoughtId = String(thought.id.uuidString.prefix(8))
        os_log("[SYNC] queueThought() — saved id=%{public}@ | %{public}@", log: syncLog_os, type: .default, thoughtId, processTag())
        addLogEntry("Queued: \(text.prefix(30))...", trigger: trigger)

        // Fire and forget - don't await so callers return immediately
        requestFlush(trigger: trigger)
    }

    /// Routes to background uploads (iOS) or direct flush (macOS).
    @discardableResult
    func requestFlush(trigger: SyncTrigger) -> Task<Int, Never> {
        os_log("[SYNC] requestFlush() — trigger=%{public}@ | %{public}@", log: syncLog_os, type: .default, trigger.rawValue, processTag())

        #if os(iOS)
        os_log("[SYNC] requestFlush() — iOS: enqueuing background uploads", log: syncLog_os, type: .default)
        enqueueBackgroundUploads(trigger: trigger)
        return Task { 0 }
        #else
        os_log("[SYNC] requestFlush() — macOS: direct flush", log: syncLog_os, type: .default)
        return Task {
            await performFlush(trigger: trigger)
        }
        #endif
    }

    // MARK: - Background Uploads (iOS)

    #if os(iOS)
    /// Creates background upload tasks for each pending thought.
    /// The OS sends these even if the app is killed/suspended.
    private func enqueueBackgroundUploads(trigger: SyncTrigger) {
        os_log("[UPLOAD] enqueueBackgroundUploads() — ENTRY trigger=%{public}@ | %{public}@", log: uploadLog, type: .default, trigger.rawValue, processTag())
        DebugFileLog.write("[UPLOAD] enqueueBackgroundUploads() trigger=\(trigger.rawValue)")

        guard let apiKey = Configuration.apiKey,
              let proxySecret = Configuration.proxySecret,
              let baseURL = Configuration.intakerURL else {
            os_log("[UPLOAD] ABORT — not configured", log: uploadLog, type: .error)
            addLogEntry("UPLOAD-ABORT not configured", trigger: trigger)
            return
        }
        guard let container = modelContainer else {
            os_log("[UPLOAD] ABORT — modelContainer is nil", log: uploadLog, type: .error)
            return
        }

        let context = container.mainContext
        let descriptor = FetchDescriptor<Thought>(sortBy: [SortDescriptor(\.createdAt)])
        guard let allThoughts = try? context.fetch(descriptor) else {
            os_log("[UPLOAD] ABORT — fetch failed", log: uploadLog, type: .error)
            return
        }

        let pending = allThoughts.filter { $0.status == .queued || $0.status == .failed }

        if pending.isEmpty {
            os_log("[UPLOAD] EMPTY — no pending thoughts", log: uploadLog, type: .default)
            addLogEntry("UPLOAD-EMPTY no pending thoughts", trigger: trigger)
            return
        }

        let pendingIds = pending.map { String($0.id.uuidString.prefix(8)) }.joined(separator: ",")
        os_log("[UPLOAD] ENQUEUING count=%d ids=[%{public}@]", log: uploadLog, type: .default, pending.count, pendingIds)
        addLogEntry("UPLOAD-ENQUEUE count=\(pending.count) ids=[\(pendingIds)]", trigger: trigger)

        // Modal proxy auth: credentials travel as headers, not a query param
        let requestURL = baseURL

        for thought in pending {
            let thoughtIdShort = String(thought.id.uuidString.prefix(8))

            // Write payload to temp file (background uploads require fromFile:)
            guard let fileURL = Self.uploadFileURL(for: thought.id) else {
                os_log("[UPLOAD] SKIP id=%{public}@ — can't get upload file URL", log: uploadLog, type: .error, thoughtIdShort)
                continue
            }

            let payload = ["raw_text": thought.text]
            guard let jsonData = try? JSONEncoder().encode(payload) else {
                os_log("[UPLOAD] SKIP id=%{public}@ — JSON encode failed", log: uploadLog, type: .error, thoughtIdShort)
                continue
            }

            do {
                try jsonData.write(to: fileURL, options: .atomic)
            } catch {
                os_log("[UPLOAD] SKIP id=%{public}@ — file write failed: %{public}@", log: uploadLog, type: .error, thoughtIdShort, error.localizedDescription)
                continue
            }

            // Build request (NO httpBody — body comes from file)
            var request = URLRequest(url: requestURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(apiKey, forHTTPHeaderField: "Modal-Key")
            request.setValue(proxySecret, forHTTPHeaderField: "Modal-Secret")

            // Create background upload task
            let task = backgroundSession.uploadTask(with: request, fromFile: fileURL)
            task.taskDescription = thought.id.uuidString  // Maps task → thought, survives relaunch
            task.resume()

            // Mark thought as sending with long lock (OS owns it now)
            thought.status = .sending
            thought.sentVia = trigger
            thought.lockedUntil = Date.distantFuture
            saveContextWithErrorHandling(context, thoughtId: thoughtIdShort)

            os_log("[UPLOAD] ENQUEUED id=%{public}@ taskId=%d file=%{public}@", log: uploadLog, type: .default, thoughtIdShort, task.taskIdentifier, fileURL.lastPathComponent)
            addLogEntry("UPLOAD-TASK id=\(thoughtIdShort) taskId=\(task.taskIdentifier)", trigger: trigger)
        }

        os_log("[UPLOAD] enqueueBackgroundUploads() — EXIT", log: uploadLog, type: .default)
    }

    /// Called by delegate when a single upload task completes.
    func handleUploadCompleted(thoughtId: UUID, statusCode: Int, error: Error?) {
        let thoughtIdShort = String(thoughtId.uuidString.prefix(8))
        os_log("[UPLOAD] handleUploadCompleted() id=%{public}@ code=%d error=%{public}@ | %{public}@", log: uploadLog, type: .default, thoughtIdShort, statusCode, error?.localizedDescription ?? "none", processTag())
        DebugFileLog.write("[UPLOAD] handleUploadCompleted id=\(thoughtIdShort) code=\(statusCode) error=\(error?.localizedDescription ?? "none")")

        guard let container = modelContainer else {
            os_log("[UPLOAD] handleUploadCompleted — ABORT: no modelContainer", log: uploadLog, type: .error)
            return
        }

        let context = container.mainContext
        let descriptor = FetchDescriptor<Thought>(predicate: #Predicate { $0.id == thoughtId })
        guard let thought = try? context.fetch(descriptor).first else {
            os_log("[UPLOAD] handleUploadCompleted — thought NOT FOUND id=%{public}@", log: uploadLog, type: .error, thoughtIdShort)
            return
        }

        // Clear the lock regardless of outcome
        thought.lockedUntil = nil

        if error == nil && (200...299).contains(statusCode) {
            // Success — sentVia already set at enqueue time with the original trigger
            thought.status = .sent
            thought.sentAt = Date()
            thought.lastError = nil
            os_log("[UPLOAD] SUCCESS id=%{public}@", log: uploadLog, type: .default, thoughtIdShort)
            addLogEntry("UPLOAD-SUCCESS id=\(thoughtIdShort) code=\(statusCode)", trigger: .backgroundWake)
        } else {
            // Failure — 4xx means the server definitively refused this payload, never auto-retry
            thought.status = (error == nil && (400...499).contains(statusCode)) ? .rejected : .failed
            thought.retryCount += 1
            thought.lastError = error?.localizedDescription ?? "HTTP \(statusCode)"
            os_log("[UPLOAD] FAILED id=%{public}@ status=%{public}@ error=%{public}@", log: uploadLog, type: .error, thoughtIdShort, thought.status.rawValue, thought.lastError ?? "unknown")
            addLogEntry("UPLOAD-FAILED id=\(thoughtIdShort) status=\(thought.status.rawValue) error=\(thought.lastError ?? "unknown")", trigger: .backgroundWake)
        }

        saveContextWithErrorHandling(context, thoughtId: thoughtIdShort)

        // Clean up temp file
        if let fileURL = Self.uploadFileURL(for: thoughtId) {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    /// Called when all background upload tasks have finished.
    func handleAllBackgroundUploadsFinished() {
        os_log("[UPLOAD] handleAllBackgroundUploadsFinished() | %{public}@", log: uploadLog, type: .default, processTag())
        DebugFileLog.write("[UPLOAD] handleAllBackgroundUploadsFinished()")

        // Count recently sent thoughts for notification
        if let container = modelContainer {
            let context = container.mainContext
            let fiveMinutesAgo = Date().addingTimeInterval(-300)
            let sentStatus = ThoughtStatus.sent
            let descriptor = FetchDescriptor<Thought>(predicate: #Predicate {
                $0.status == sentStatus && $0.sentAt != nil && $0.sentAt! > fiveMinutesAgo
            })
            if let recentlySent = try? context.fetch(descriptor), !recentlySent.isEmpty {
                Task {
                    await sendNotification(count: recentlySent.count, trigger: .backgroundWake)
                }
            }
        }

        // Call the OS completion handler
        backgroundSessionCompletionHandler?()
        backgroundSessionCompletionHandler = nil
    }

    /// Reduces locks on .sending thoughts from .distantFuture to a short grace period.
    /// Called when the app becomes active so delegate callbacks have a window to fire.
    func reduceSendingLocks() {
        os_log("[UPLOAD] reduceSendingLocks() | %{public}@", log: uploadLog, type: .default, processTag())

        guard let container = modelContainer else { return }
        let context = container.mainContext

        let sendingStatus = ThoughtStatus.sending
        let descriptor = FetchDescriptor<Thought>(predicate: #Predicate {
            $0.status == sendingStatus
        })
        guard let sendingThoughts = try? context.fetch(descriptor) else { return }

        let gracePeriod = Date().addingTimeInterval(10)
        var reducedCount = 0

        for thought in sendingThoughts {
            if thought.lockedUntil == Date.distantFuture {
                thought.lockedUntil = gracePeriod
                reducedCount += 1
            }
        }

        if reducedCount > 0 {
            saveContextWithErrorHandling(context)
            os_log("[UPLOAD] Reduced %d sending locks to 10s grace", log: uploadLog, type: .default, reducedCount)
            addLogEntry("LOCK-REDUCE count=\(reducedCount) grace=10s", trigger: .appBecameActive)

            // Schedule orphan recovery after grace period
            Task {
                try? await Task.sleep(for: .seconds(12))
                await recoverOrphanedUploads()
            }
        }
    }

    /// Checks for .sending thoughts with expired locks and no matching background task.
    /// Resets them to .queued so they can be re-sent.
    private func recoverOrphanedUploads() {
        os_log("[UPLOAD] recoverOrphanedUploads() | %{public}@", log: uploadLog, type: .default, processTag())

        guard let container = modelContainer else { return }
        let context = container.mainContext
        let now = Date()

        let sendingStatus = ThoughtStatus.sending
        let descriptor = FetchDescriptor<Thought>(predicate: #Predicate {
            $0.status == sendingStatus
        })
        guard let sendingThoughts = try? context.fetch(descriptor) else { return }

        // Filter to those with expired locks
        let orphanCandidates = sendingThoughts.filter {
            guard let lockedUntil = $0.lockedUntil else { return true }
            return lockedUntil <= now
        }

        if orphanCandidates.isEmpty {
            os_log("[UPLOAD] No orphan candidates", log: uploadLog, type: .default)
            return
        }

        // Check background session for active tasks
        backgroundSession.getAllTasks { [weak self] tasks in
            let activeTaskIds = Set(tasks.compactMap { $0.taskDescription })

            Task { @MainActor in
                guard let self else { return }
                var recoveredCount = 0

                for thought in orphanCandidates {
                    if !activeTaskIds.contains(thought.id.uuidString) {
                        let thoughtIdShort = String(thought.id.uuidString.prefix(8))
                        os_log("[UPLOAD] ORPHAN-RECOVER id=%{public}@ — resetting to .queued", log: uploadLog, type: .default, thoughtIdShort)
                        thought.status = .queued
                        thought.lockedUntil = nil
                        recoveredCount += 1

                        // Clean up stale upload file
                        if let fileURL = Self.uploadFileURL(for: thought.id) {
                            try? FileManager.default.removeItem(at: fileURL)
                        }
                    }
                }

                if recoveredCount > 0 {
                    self.saveContextWithErrorHandling(context)
                    self.addLogEntry("ORPHAN-RECOVER count=\(recoveredCount)", trigger: .appBecameActive)
                    os_log("[UPLOAD] Recovered %d orphaned thoughts", log: uploadLog, type: .default, recoveredCount)
                }
            }
        }
    }
    #endif

    // MARK: - Direct Flush (macOS)

    #if os(macOS)
    /// The direct flush implementation with per-item locking. Used on macOS where the app stays running.
    private func performFlush(trigger: SyncTrigger) async -> Int {
        os_log("[FLUSH] performFlush() — ENTRY online=%{public}d trigger=%{public}@ | %{public}@", log: flushLog, type: .default, isOnline ? 1 : 0, trigger.rawValue, processTag())
        DebugFileLog.write("[FLUSH] performFlush() entry trigger=\(trigger.rawValue)")

        guard isOnline else {
            os_log("[FLUSH] SKIP — offline", log: flushLog, type: .default)
            addLogEntry("FLUSH-SKIP offline", trigger: trigger)
            return 0
        }
        guard let container = modelContainer else {
            os_log("[FLUSH] SKIP — modelContainer is nil", log: flushLog, type: .error)
            return 0
        }

        isSyncing = true
        defer { isSyncing = false }

        let context = container.mainContext

        let descriptor = FetchDescriptor<Thought>(sortBy: [SortDescriptor(\.createdAt)])
        guard let allThoughts = try? context.fetch(descriptor) else {
            os_log("[FLUSH] SKIP — fetch failed", log: flushLog, type: .error)
            return 0
        }

        let thoughts = allThoughts.filter {
            $0.status == .queued || $0.status == .failed
        }

        if thoughts.isEmpty {
            os_log("[FLUSH] EMPTY — no pending thoughts", log: flushLog, type: .default)
            addLogEntry("FLUSH-EMPTY queue has no pending thoughts", trigger: trigger)
            return 0
        }

        let thoughtIds = thoughts.map { String($0.id.uuidString.prefix(8)) }.joined(separator: ",")
        os_log("[FLUSH] START count=%d ids=[%{public}@] | %{public}@", log: flushLog, type: .default, thoughts.count, thoughtIds, processTag())
        addLogEntry("FLUSH-START count=\(thoughts.count) ids=[\(thoughtIds)]", trigger: trigger)

        var successCount = 0

        for (index, thought) in thoughts.enumerated() {
            let thoughtId = thought.id
            let thoughtIdShort = String(thoughtId.uuidString.prefix(8))

            os_log("[FLUSH] processing %d/%d id=%{public}@", log: flushLog, type: .default, index + 1, thoughts.count, thoughtIdShort)

            // FRESH FETCH: Re-fetch this specific thought to get current lock/status state
            let freshDescriptor = FetchDescriptor<Thought>(predicate: #Predicate { $0.id == thoughtId })
            guard let freshThought = try? context.fetch(freshDescriptor).first else {
                os_log("[FLUSH] SKIP-NOT-FOUND id=%{public}@", log: flushLog, type: .default, thoughtIdShort)
                addLogEntry("SKIP-NOT-FOUND id=\(thoughtIdShort)", trigger: trigger)
                continue
            }

            // Check if this thought is currently locked by another flush
            let now = Date()
            if let lockedUntil = freshThought.lockedUntil, lockedUntil > now {
                let remaining = lockedUntil.timeIntervalSince(now)
                os_log("[FLUSH] SKIP-LOCKED id=%{public}@ remaining=%.1fs", log: flushLog, type: .default, thoughtIdShort, remaining)
                addLogEntry("SKIP-LOCKED id=\(thoughtIdShort) remaining=\(String(format: "%.1f", remaining))s", trigger: trigger)
                continue
            }

            // Check if status changed (e.g., already sending or sent)
            if freshThought.status == .sending || freshThought.status == .sent {
                os_log("[FLUSH] SKIP-STATUS id=%{public}@ status=%{public}@", log: flushLog, type: .default, thoughtIdShort, freshThought.status.rawValue)
                addLogEntry("SKIP-STATUS id=\(thoughtIdShort) status=\(freshThought.status.rawValue)", trigger: trigger)
                continue
            }

            // Acquire lock on this thought
            freshThought.lockedUntil = Date().addingTimeInterval(lockDuration)
            saveContextWithErrorHandling(context, thoughtId: thoughtIdShort)

            let success = await receptThought(freshThought, trigger: trigger)

            if success {
                freshThought.lockedUntil = nil
                saveContextWithErrorHandling(context, thoughtId: thoughtIdShort)
                successCount += 1
                os_log("[FLUSH] item %d/%d SUCCESS id=%{public}@", log: flushLog, type: .default, index + 1, thoughts.count, thoughtIdShort)
            } else if freshThought.status == .rejected {
                // Permanent server rejection — skip it so it can't wedge the queue
                freshThought.lockedUntil = nil
                saveContextWithErrorHandling(context, thoughtId: thoughtIdShort)
                os_log("[FLUSH] SKIP-REJECTED id=%{public}@ — continuing flush", log: flushLog, type: .error, thoughtIdShort)
                addLogEntry("SKIP-REJECTED id=\(thoughtIdShort)", trigger: trigger)
            } else {
                freshThought.lockedUntil = nil
                saveContextWithErrorHandling(context, thoughtId: thoughtIdShort)
                os_log("[FLUSH] STOP — failure on id=%{public}@ after %d sent", log: flushLog, type: .error, thoughtIdShort, successCount)
                addLogEntry("FLUSH-STOP failure on id=\(thoughtIdShort) after \(successCount) sent", trigger: trigger)
                break
            }
        }

        // One batch notification at the end (not per-thought)
        if successCount > 0 && trigger != .captureIntent {
            await sendNotification(count: successCount, trigger: trigger)
        }

        if successCount > 0 {
            os_log("[FLUSH] COMPLETE sent=%d | %{public}@", log: flushLog, type: .default, successCount, processTag())
            addLogEntry("FLUSH-COMPLETE sent=\(successCount)", trigger: trigger)
        }

        os_log("[FLUSH] performFlush() — EXIT sent=%d", log: flushLog, type: .default, successCount)
        return successCount
    }

    /// Sends a single thought to the processor. Blocking - waits for the response.
    private func receptThought(_ thought: Thought, trigger: SyncTrigger) async -> Bool {
        let thoughtIdShort = String(thought.id.uuidString.prefix(8))

        guard let apiKey = Configuration.apiKey,
              let proxySecret = Configuration.proxySecret,
              let baseURL = Configuration.intakerURL else {
            os_log("[HTTP] FAIL id=%{public}@ reason=not_configured | %{public}@", log: httpLog, type: .error, thoughtIdShort, processTag())
            addLogEntry("SEND-FAIL id=\(thoughtIdShort) reason=not_configured", trigger: trigger)
            return false
        }

        os_log("[HTTP] SEND-START id=%{public}@ text='%{public}@' attempt=%d | %{public}@", log: httpLog, type: .default, thoughtIdShort, String(thought.text.prefix(20)), thought.retryCount + 1, processTag())
        addLogEntry("SEND-START id=\(thoughtIdShort) text='\(thought.text.prefix(20))' attempt=\(thought.retryCount + 1)", trigger: trigger)

        // Modal proxy auth: credentials travel as headers, not a query param
        let requestURL = baseURL
        os_log("[HTTP] URL=%{public}@", log: httpLog, type: .default, requestURL.absoluteString)

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "Modal-Key")
        request.setValue(proxySecret, forHTTPHeaderField: "Modal-Secret")
        request.timeoutInterval = 30

        let payload = ["raw_text": thought.text]
        request.httpBody = try? JSONEncoder().encode(payload)

        thought.status = .sending
        addLogEntry("STATUS→sending id=\(thoughtIdShort)", trigger: trigger)
        saveContextWithErrorHandling(modelContainer?.mainContext, thoughtId: thoughtIdShort)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                // 4xx = the server definitively refused this payload; retrying can never succeed
                thought.status = (400...499).contains(statusCode) ? .rejected : .failed
                thought.retryCount += 1
                thought.lastError = "Server error: \(statusCode)"
                os_log("[HTTP] FAIL id=%{public}@ code=%d status=%{public}@", log: httpLog, type: .error, thoughtIdShort, statusCode, thought.status.rawValue)
                addLogEntry("HTTP-FAIL id=\(thoughtIdShort) code=\(statusCode) status=\(thought.status.rawValue)", trigger: trigger)
                saveContextWithErrorHandling(modelContainer?.mainContext, thoughtId: thoughtIdShort)
                return false
            }

            os_log("[HTTP] SUCCESS id=%{public}@ code=%d", log: httpLog, type: .default, thoughtIdShort, httpResponse.statusCode)
            addLogEntry("HTTP-SUCCESS id=\(thoughtIdShort) code=\(httpResponse.statusCode)", trigger: trigger)

            thought.status = .sent
            thought.sentAt = Date()
            thought.sentVia = trigger
            thought.lastError = nil
            addLogEntry("STATUS→sent id=\(thoughtIdShort)", trigger: trigger)
            saveContextWithErrorHandling(modelContainer?.mainContext, thoughtId: thoughtIdShort)
            return true
        } catch {
            thought.status = .failed
            thought.retryCount += 1
            thought.lastError = error.localizedDescription
            os_log("[HTTP] ERROR id=%{public}@ error=%{public}@", log: httpLog, type: .error, thoughtIdShort, error.localizedDescription)
            addLogEntry("HTTP-ERROR id=\(thoughtIdShort) error=\(error.localizedDescription)", trigger: trigger)
            saveContextWithErrorHandling(modelContainer?.mainContext, thoughtId: thoughtIdShort)
            return false
        }
    }
    #endif

    // MARK: - DB Save with Error Handling

    private func saveContextWithErrorHandling(_ context: ModelContext?, thoughtId: String? = nil) {
        guard let context else { return }
        do {
            try context.save()
            if let id = thoughtId {
                addLogEntry("SAVE-SUCCESS id=\(id)", trigger: .appBecameActive)
            }
        } catch {
            let idInfo = thoughtId.map { " id=\($0)" } ?? ""
            os_log("[SYNC] SAVE-FAILED%{public}@ error=%{public}@", log: syncLog_os, type: .error, idInfo, error.localizedDescription)
            addLogEntry("SAVE-FAILED\(idInfo) error=\(error.localizedDescription)", trigger: .appBecameActive)
            Task {
                await sendNotification(title: "Receptor - DB Error", body: "Failed to save: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Sync Log (SwiftData-backed)

    private func addLogEntry(_ message: String, trigger: SyncTrigger) {
        // Always mirror to os_log first — works even when modelContainer is nil
        os_log("[SYNC] LOG: [%{public}@] %{public}@ | %{public}@", log: syncLog_os, type: .default, trigger.rawValue, message, processTag())

        guard let container = modelContainer else {
            os_log("[SYNC] addLogEntry() — SKIP SwiftData insert: modelContainer is nil", log: syncLog_os, type: .fault)
            return
        }

        let entry = SyncLogEntry(timestamp: Date(), message: message, trigger: trigger)
        container.mainContext.insert(entry)

        // Don't save on every log entry - it'll be saved with the next context save
        // But we do need to update the published array for UI
        syncLog.insert(entry, at: 0)
    }

    private func loadSyncLog() {
        guard let container = modelContainer else { return }

        var descriptor = FetchDescriptor<SyncLogEntry>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        descriptor.fetchLimit = 50  // Only load recent entries for UI

        if let entries = try? container.mainContext.fetch(descriptor) {
            syncLog = entries
        }
    }

    /// Exports all sync logs to a file on a background thread.
    /// Returns the file URL for sharing, or nil on failure.
    nonisolated func exportLogs() async -> URL? {
        os_log("[EXPORT] Starting export... | %{public}@", log: exportLog, type: .default, processTag())

        guard let container = await modelContainer else {
            os_log("[EXPORT] FAILED: No model container", log: exportLog, type: .error)
            return nil
        }
        os_log("[EXPORT] Got container", log: exportLog, type: .default)

        // Create a background context - this runs OFF the main thread
        let backgroundContext = ModelContext(container)
        os_log("[EXPORT] Created background context", log: exportLog, type: .default)

        // Fetch on background thread
        let descriptor = FetchDescriptor<SyncLogEntry>(sortBy: [SortDescriptor(\.timestamp, order: .forward)])

        let entries: [SyncLogEntry]
        do {
            entries = try backgroundContext.fetch(descriptor)
            os_log("[EXPORT] Fetched %d entries", log: exportLog, type: .default, entries.count)
        } catch {
            os_log("[EXPORT] FAILED: Fetch error - %{public}@", log: exportLog, type: .error, error.localizedDescription)
            return nil
        }

        // Build string efficiently using array join (O(n) instead of O(n²))
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        var lines: [String] = []
        lines.reserveCapacity(entries.count + 30)

        lines.append("Receptor Sync Log - Exported \(dateFormatter.string(from: Date()))")
        lines.append(String(repeating: "=", count: 60))
        lines.append("")

        for entry in entries {
            let timestamp = dateFormatter.string(from: entry.timestamp)
            lines.append("[\(timestamp)] [\(entry.trigger.rawValue)] \(entry.message)")
        }

        lines.append("")
        lines.append("Total entries: \(entries.count)")

        // Append DebugFileLog contents
        lines.append("")
        lines.append(String(repeating: "=", count: 60))
        lines.append("DEBUG FILE LOG (raw file writes)")
        lines.append(String(repeating: "=", count: 60))
        lines.append("")

        if let debugContents = DebugFileLog.readAll(), !debugContents.isEmpty {
            lines.append(debugContents)
        } else {
            lines.append("(no debug file log entries)")
        }

        // Append os_log retrieval instructions
        lines.append("")
        lines.append(String(repeating: "=", count: 60))
        lines.append("OS LOG RETRIEVAL")
        lines.append(String(repeating: "=", count: 60))
        lines.append("")
        lines.append("To stream os_log in real-time from Mac:")
        lines.append("  log stream --predicate 'subsystem == \"com.alexmiller.receptor\"' --level debug --style compact")
        lines.append("")
        lines.append("To collect recent os_log from connected iOS device:")
        lines.append("  log collect --device --last 1h --output receptor.logarchive")
        lines.append("  log show receptor.logarchive --predicate 'subsystem == \"com.alexmiller.receptor\"' --style compact")

        let logContent = lines.joined(separator: "\n")
        os_log("[EXPORT] Built log content (%d chars)", log: exportLog, type: .default, logContent.count)

        // Write file (still on background thread)
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileURL = documentsURL.appendingPathComponent("receptor.log")
        os_log("[EXPORT] Writing to: %{public}@", log: exportLog, type: .default, fileURL.path)

        do {
            try logContent.write(to: fileURL, atomically: true, encoding: .utf8)
            os_log("[EXPORT] SUCCESS: File written", log: exportLog, type: .default)
            return fileURL
        } catch {
            os_log("[EXPORT] FAILED: Write error - %{public}@", log: exportLog, type: .error, error.localizedDescription)
            return nil
        }
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

        // On iOS, background task triggers background uploads too
        SyncManager.shared.enqueueBackgroundUploads(trigger: .backgroundTask)
        task.setTaskCompleted(success: true)
    }
    #endif
}

// MARK: - Background URLSession Delegate

/// Handles completion of background upload tasks. Must be a separate non-MainActor class
/// because URLSessionDelegate callbacks are called on the delegate queue.
final class BackgroundSessionDelegate: NSObject, URLSessionDataDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let sessionId = session.configuration.identifier ?? "unknown"
        let statusCode = (task.response as? HTTPURLResponse)?.statusCode ?? 0
        let thoughtIdString = task.taskDescription ?? "unknown"

        if let error = error {
            os_log("[DELEGATE] didCompleteWithError — session=%{public}@ taskId=%d thoughtId=%{public}@ code=%d error=%{public}@ | %{public}@", log: delegateLog, type: .error, sessionId, task.taskIdentifier, thoughtIdString, statusCode, error.localizedDescription, processTag())
        } else {
            os_log("[DELEGATE] didCompleteWithError — session=%{public}@ taskId=%d thoughtId=%{public}@ code=%d (no error) | %{public}@", log: delegateLog, type: .default, sessionId, task.taskIdentifier, thoughtIdString, statusCode, processTag())
        }
        DebugFileLog.write("[DELEGATE] didComplete session=\(sessionId) taskId=\(task.taskIdentifier) thoughtId=\(thoughtIdString) code=\(statusCode) error=\(error?.localizedDescription ?? "none")")

        #if os(iOS)
        // Extract thought UUID from task description and notify SyncManager
        if let uuidString = task.taskDescription, let thoughtId = UUID(uuidString: uuidString) {
            Task { @MainActor in
                SyncManager.shared.handleUploadCompleted(thoughtId: thoughtId, statusCode: statusCode, error: error)
            }
        }
        #endif
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let sessionId = session.configuration.identifier ?? "unknown"
        os_log("[DELEGATE] urlSessionDidFinishEvents — session=%{public}@ | %{public}@", log: delegateLog, type: .default, sessionId, processTag())
        DebugFileLog.write("[DELEGATE] urlSessionDidFinishEvents session=\(sessionId)")

        #if os(iOS)
        Task { @MainActor in
            SyncManager.shared.handleAllBackgroundUploadsFinished()
        }
        #endif
    }
}

// MARK: - Supporting Types

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
