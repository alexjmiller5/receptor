import Foundation
import SwiftData

/// The share-sheet extensions' capture path: persist the thought in the shared
/// store, upload it right away while the extension is alive, and record what
/// actually happened. Anything that did not go through stays `.queued` for the
/// app's normal flush.
enum ShareCapture {
    enum Outcome {
        case sent
        case queued
        case unauthorized
        case rejected(Int)
    }

    static func makeContainer() throws -> ModelContainer {
        guard let url = Configuration.storeURL else { throw ShareCaptureError.noContainer }
        return try ModelContainer(for: Thought.self, SyncLogEntry.self, configurations: ModelConfiguration(url: url))
    }

    @MainActor
    static func capture(text: String, source: String, container: ModelContainer) async throws -> Outcome {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ShareCaptureError.emptyText }
        let context = container.mainContext
        let thought = Thought(text: trimmed, source: source)
        // Held while this upload runs so an app flush in the same seconds
        // does not send it a second time.
        thought.lockedUntil = Date().addingTimeInterval(20)
        context.insert(thought)
        context.insert(SyncLogEntry(timestamp: Date(), message: "Queued (share sheet): \(trimmed.prefix(30))...", trigger: .shareExtension))
        try context.save()
        let id = String(thought.id.uuidString.prefix(8))

        var outcome = Outcome.queued
        if let token = Configuration.captureToken,
           let url = Configuration.intakerURL,
           let body = try? JSONEncoder().encode(thought.uploadPayload) {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 10
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            if let (_, response) = try? await URLSession.shared.data(for: request),
               let http = response as? HTTPURLResponse {
                switch ThoughtStatus.after(httpStatus: http.statusCode) {
                case .sent:
                    thought.status = .sent
                    thought.sentAt = Date()
                    thought.sentVia = .shareExtension
                    outcome = .sent
                case .rejected:
                    thought.status = .rejected
                    thought.retryCount += 1
                    thought.lastError = "HTTP \(http.statusCode)"
                    outcome = .rejected(http.statusCode)
                default:
                    if http.statusCode == 401 || http.statusCode == 403 { outcome = .unauthorized }
                }
            }
        }
        thought.lockedUntil = nil
        try context.save()
        DebugFileLog.write("[SHARE] id=\(id) source=\(source) outcome=\(outcome)")
        return outcome
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
