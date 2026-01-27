import AppIntents
import SwiftData
import Foundation

/// App Intent for recepting the thought queue - used by Automations and manual triggers
struct ReceptQueueIntent: AppIntent {
    static var title: LocalizedStringResource = "Recept Thought Queue"
    static var description = IntentDescription("Recept all queued thoughts in the queue to the processor")

    static var parameterSummary: some ParameterSummary {
        Summary("Recept thought queue")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        // Ensure SyncManager has access to the shared container
        if SyncManager.shared.modelContainer == nil {
            let container = try ModelContainer(
                for: Thought.self,
                configurations: ModelConfiguration(
                    url: Configuration.sharedContainerURL!.appendingPathComponent("Receptor.sqlite")
                )
            )
            SyncManager.shared.configure(with: container)
        }

        // Fire-and-forget — background wake will handle the actual flush
        SyncManager.shared.requestFlush(trigger: .flushIntent)

        return .result(value: "Recept requested")
    }
}
