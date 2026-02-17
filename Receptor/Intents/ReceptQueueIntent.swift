import AppIntents
import SwiftData
import Foundation
import os.log

private let intentLog = OSLog(subsystem: "com.alexmiller.receptor", category: "Intent")

/// App Intent for recepting the thought queue - used by Automations and manual triggers
struct ReceptQueueIntent: AppIntent {
    static var title: LocalizedStringResource = "Recept Thought Queue"
    static var description = IntentDescription("Recept all queued thoughts in the queue to the processor")

    static var parameterSummary: some ParameterSummary {
        Summary("Recept thought queue")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let pid = ProcessInfo.processInfo.processIdentifier
        let proc = ProcessInfo.processInfo.processName
        os_log("[INTENT] ReceptQueueIntent.perform() — ENTRY pid=%d proc=%{public}@", log: intentLog, type: .default, pid, proc)
        DebugFileLog.write("[INTENT] ReceptQueueIntent.perform() ENTRY pid=\(pid) proc=\(proc)")

        // Ensure SyncManager has access to the shared container
        let containerWasNil = SyncManager.shared.modelContainer == nil
        os_log("[INTENT] ReceptQueueIntent — containerWasNil=%{public}d", log: intentLog, type: .default, containerWasNil ? 1 : 0)

        if containerWasNil {
            os_log("[INTENT] ReceptQueueIntent — creating ModelContainer (force-quit scenario)", log: intentLog, type: .default)
            let container = try ModelContainer(
                for: Thought.self, SyncLogEntry.self,
                configurations: ModelConfiguration(
                    url: Configuration.sharedContainerURL!.appendingPathComponent("Receptor.sqlite")
                )
            )
            SyncManager.shared.configure(with: container)
            os_log("[INTENT] ReceptQueueIntent — ModelContainer created and configured", log: intentLog, type: .default)
        }

        // Fire-and-forget — background wake will handle the actual flush
        SyncManager.shared.requestFlush(trigger: .flushIntent)

        os_log("[INTENT] ReceptQueueIntent.perform() — EXIT returning 'Recept requested'", log: intentLog, type: .default)
        return .result(value: "Recept requested")
    }
}
