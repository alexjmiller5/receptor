import Foundation
import SwiftData

enum ThoughtStatus: String, Codable {
    case queued = "queued"
    case sending = "sending"
    case sent = "sent"
    case failed = "failed"
}

enum SyncTrigger: String, Codable {
    case captureIntent = "Capture Intent"
    case flushIntent = "Flush Intent"
    case backgroundTask = "Background Task"
    case appBecameActive = "App Opened"
    case networkRestored = "Network Restored"
    case manualRetry = "Manual Retry"
    case pullToRefresh = "Pull to Refresh"
    case backgroundWake = "Background Wake"
}

@Model
final class Thought {
    var id: UUID
    var text: String
    var createdAt: Date
    var sentAt: Date?
    var status: ThoughtStatus
    var retryCount: Int
    var lastError: String?
    var sentVia: SyncTrigger?

    init(text: String) {
        self.id = UUID()
        self.text = text
        self.createdAt = Date()
        self.sentAt = nil
        self.status = .queued
        self.retryCount = 0
        self.lastError = nil
        self.sentVia = nil
    }
}
