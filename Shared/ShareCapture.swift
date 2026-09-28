import Foundation
import SwiftData

/// The share-sheet extensions' capture path: persist the thought in the shared store
/// and hand its upload to the OS through a background URLSession. The extension
/// exits right after; the app owns the session's completion (see
/// `SyncManager.reconnectBackgroundSession` and AppDelegate).
enum ShareCapture {
    static let backgroundSessionIdentifier = "com.alexmiller.receptor.share-upload"

    static func makeContainer() throws -> ModelContainer {
        guard let url = Configuration.storeURL else { throw ShareCaptureError.noContainer }
        return try ModelContainer(for: Thought.self, SyncLogEntry.self, configurations: ModelConfiguration(url: url))
    }

    @MainActor
    static func enqueue(text: String, source: String, container: ModelContainer) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ShareCaptureError.emptyText }
        let context = container.mainContext
        let thought = Thought(text: trimmed, source: source)
        context.insert(thought)
        context.insert(SyncLogEntry(timestamp: Date(), message: "Queued (share sheet): \(trimmed.prefix(30))...", trigger: .shareExtension))
        try context.save()
        DebugFileLog.write("[SHARE] queued id=\(thought.id.uuidString.prefix(8))")

        // Not configured: leave it .queued; the app flushes it after setup and
        // warns the user itself.
        guard let apiKey = Configuration.apiKey,
              let proxySecret = Configuration.proxySecret,
              let baseURL = Configuration.intakerURL,
              let fileURL = Configuration.uploadFileURL(for: thought.id),
              let body = try? JSONEncoder().encode(thought.uploadPayload) else { return }
        try body.write(to: fileURL, options: .atomic)

        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "Modal-Key")
        request.setValue(proxySecret, forHTTPHeaderField: "Modal-Secret")

        let config = URLSessionConfiguration.background(withIdentifier: backgroundSessionIdentifier)
        config.sharedContainerIdentifier = Configuration.appGroupIdentifier
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.waitsForConnectivity = true
        let task = URLSession(configuration: config).uploadTask(with: request, fromFile: fileURL)
        task.taskDescription = thought.id.uuidString
        task.resume()

        thought.status = .sending
        thought.sentVia = .shareExtension
        thought.lockedUntil = .distantFuture
        try context.save()
        DebugFileLog.write("[SHARE] upload enqueued id=\(thought.id.uuidString.prefix(8)) taskId=\(task.taskIdentifier)")
    }
}

enum ShareCaptureError: LocalizedError {
    case noContainer, emptyText
    var errorDescription: String? {
        switch self {
        case .noContainer: "App Group container unavailable"
        case .emptyText: "Nothing to send"
        }
    }
}
