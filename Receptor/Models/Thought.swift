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
    case composeButton = "Compose Button"
    case backgroundWake = "Background Wake"

    var codeName: String {
        switch self {
        case .captureIntent: "CaptureThoughtIntent.perform()"
        case .flushIntent: "ReceptQueueIntent.perform()"
        case .backgroundTask: "handleBackgroundTask()"
        case .appBecameActive: "applicationDidBecomeActive()"
        case .networkRestored: "pathUpdateHandler()"
        case .composeButton: "ComposeView.send()"
        case .manualRetry: "manualRetry"
        case .pullToRefresh: "pullToRefresh"
        case .backgroundWake: "backgroundSession.uploadTask()"
        }
    }
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
    var lockedUntil: Date?

    init(text: String) {
        self.id = UUID()
        self.text = text
        self.createdAt = Date()
        self.sentAt = nil
        self.status = .queued
        self.retryCount = 0
        self.lastError = nil
        self.sentVia = nil
        self.lockedUntil = nil
    }
}

@Model
final class SyncLogEntry {
    var id: UUID
    var timestamp: Date
    var message: String
    var trigger: SyncTrigger

    init(timestamp: Date, message: String, trigger: SyncTrigger) {
        self.id = UUID()
        self.timestamp = timestamp
        self.message = message
        self.trigger = trigger
    }
}
