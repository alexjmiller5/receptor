import AppIntents
import SwiftData
import Foundation
import os.log
import UserNotifications

private let intentLog = OSLog(subsystem: "com.alexmiller.receptor", category: "Intent")

/// App Intent that allows Shortcuts to recept thoughts through Receptor
/// This is the "fire and forget" intent - saves instantly and returns
struct CaptureThoughtIntent: AppIntent {
    static var title: LocalizedStringResource = "Recept"
    static var description = IntentDescription("Recept a thought to the processor")

    // No value given (Shortcuts widget, Control Center "Shortcut" control, Siri,
    // Spotlight) -> iOS asks in a system sheet with a multi-line field, no app
    // launch. No result dialog: the sheet closes itself once the thought is in.
    @Parameter(
        title: "Thought",
        inputOptions: String.IntentInputOptions(keyboardType: .default, capitalizationType: .sentences, multiline: true, autocorrect: true),
        requestValueDialog: "Enter your thought 💭"
    )
    var text: String

    /// Who is sending: a shortcut passes its own name, a hotkey or agent its
    /// label. Logged on the Synapse execution as `Source`; free-form.
    @Parameter(title: "Source", description: "Where this thought comes from (shortcut name, hotkey, agent)")
    var source: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Recept \(\.$text)") {
            \.$source
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let pid = ProcessInfo.processInfo.processIdentifier
        let proc = ProcessInfo.processInfo.processName
        os_log("[INTENT] CaptureThoughtIntent.perform() — ENTRY pid=%d proc=%{public}@ text='%{public}@'", log: intentLog, type: .default, pid, proc, String(text.prefix(30)))
        DebugFileLog.write("[INTENT] CaptureThoughtIntent.perform() ENTRY pid=\(pid) proc=\(proc)")

        // Ensure SyncManager has access to the shared container
        let containerWasNil = SyncManager.shared.modelContainer == nil
        os_log("[INTENT] CaptureThoughtIntent — containerWasNil=%{public}d", log: intentLog, type: .default, containerWasNil ? 1 : 0)

        if containerWasNil {
            os_log("[INTENT] CaptureThoughtIntent — creating ModelContainer (force-quit scenario)", log: intentLog, type: .default)
            let container = try ModelContainer(
                for: Thought.self, SyncLogEntry.self,
                configurations: ModelConfiguration(url: Configuration.storeURL!)
            )
            SyncManager.shared.configure(with: container)
            os_log("[INTENT] CaptureThoughtIntent — ModelContainer created and configured", log: intentLog, type: .default)
        }

        // 1. Instant Persistence - save to shared database
        await SyncManager.shared.queueThought(text, source: source ?? "app-shortcut")

        // The queueThought method already triggers background upload
        // We return immediately - the background session handles the rest

        // 2. Instant User Feedback — "Queued" must not read as "delivered" when
        // the app has no URL/tokens: nothing will ever leave the queue.
        let result = Configuration.isConfigured
            ? "Queued"
            : "Queued locally — Receptor is not configured (open Settings)"
        if Configuration.isConfigured {
            // The Shortcut showed a checkmark when it finished; this is the
            // same beat, with the text. Not configured has its own warning.
            let content = UNMutableNotificationContent()
            content.title = "Receptor 💭 ✓"
            content.body = String(text.prefix(200))
            try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
        os_log("[INTENT] CaptureThoughtIntent.perform() — EXIT returning '%{public}@'", log: intentLog, type: .default, result)
        return .result(value: result)
    }
}

/// Shortcuts that appear in the Shortcuts app
struct ReceptorShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CaptureThoughtIntent(),
            phrases: [
                "Recept in \(.applicationName)",
                "Send to \(.applicationName)",
                "\(.applicationName) recept"
            ],
            shortTitle: "Recept",
            systemImageName: "brain.head.profile"
        )
        AppShortcut(
            intent: ReceptQueueIntent(),
            phrases: [
                "Recept queue in \(.applicationName)",
                "Recept thoughts in \(.applicationName)",
                "\(.applicationName) recept queue"
            ],
            shortTitle: "Recept Thought Queue",
            systemImageName: "arrow.triangle.2.circlepath"
        )
    }
}
