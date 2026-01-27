import AppIntents
import SwiftData
import Foundation

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

        // 1. Instant Persistence - save to shared database
        await SyncManager.shared.queueThought(text)

        // The queueThought method already triggers background upload
        // We return immediately - the background session handles the rest

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
