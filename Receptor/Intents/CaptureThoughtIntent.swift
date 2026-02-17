import AppIntents
import SwiftData
import Foundation
import os.log

private let intentLog = OSLog(subsystem: "com.alexmiller.receptor", category: "Intent")

/// App Intent that allows Shortcuts to recept thoughts through Receptor
/// This is the "fire and forget" intent - saves instantly and returns
struct CaptureThoughtIntent: AppIntent {
    static var title: LocalizedStringResource = "Recept"
    static var description = IntentDescription("Recept a thought to the processor")

    @Parameter(title: "Thought")
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("Recept \(\.$text)")
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
                configurations: ModelConfiguration(
                    url: Configuration.sharedContainerURL!.appendingPathComponent("Receptor.sqlite")
                )
            )
            SyncManager.shared.configure(with: container)
            os_log("[INTENT] CaptureThoughtIntent — ModelContainer created and configured", log: intentLog, type: .default)
        }

        // 1. Instant Persistence - save to shared database
        await SyncManager.shared.queueThought(text)

        // The queueThought method already triggers background upload
        // We return immediately - the background session handles the rest

        os_log("[INTENT] CaptureThoughtIntent.perform() — EXIT returning 'Queued'", log: intentLog, type: .default)

        // 2. Instant User Feedback
        return .result(value: "Queued")
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
