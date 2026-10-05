import AppIntents
import Foundation

#if !RECEPTOR_WIDGET
import SwiftData
import os.log

private let intentLog = OSLog(subsystem: "com.alexmiller.receptor", category: "Intent")
#endif

/// App Intent that allows Shortcuts to recept thoughts through Receptor
/// This is the "fire and forget" intent - saves instantly and returns
struct CaptureThoughtIntent: AppIntent {
    static let title: LocalizedStringResource = "Recept"
    static let description = IntentDescription("Recept a thought to the processor")

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

    #if RECEPTOR_WIDGET
    private static func rejectExtensionExecution() throws -> String {
        throw CaptureExecutionError.requiresContainingApp
    }
    #endif

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        #if RECEPTOR_WIDGET
        // LiveActivityIntent routes execution to the containing app. Never
        // silently report a capture if the system invokes the extension.
        return .result(value: try Self.rejectExtensionExecution())
        #else
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
        guard await SyncManager.shared.queueThought(text, source: source ?? "app-shortcut") else {
            throw CaptureSaveError.failed
        }

        // The queueThought method already triggers background upload
        // We return immediately - the background session handles the rest

        // 2. Instant User Feedback — "Queued" must not read as "delivered" when
        // the app has no URL/tokens: nothing will ever leave the queue.
        let result = Configuration.isConfigured
            ? "Queued"
            : "Queued locally — Receptor is not configured (open Settings)"
        os_log("[INTENT] CaptureThoughtIntent.perform() — EXIT returning '%{public}@'", log: intentLog, type: .default, result)
        return .result(value: result)
        #endif
    }
}

private enum CaptureSaveError: Error, CustomLocalizedStringResourceConvertible {
    case failed
    var localizedStringResource: LocalizedStringResource {
        "The thought could not be saved. Please try again in Receptor."
    }
}

#if os(iOS)
// Persistence and the background URLSession must run in Receptor, not WidgetKit.
extension CaptureThoughtIntent: LiveActivityIntent {}
#endif

#if RECEPTOR_WIDGET
private enum CaptureExecutionError: Error {
    case requiresContainingApp
}
#endif

#if !RECEPTOR_WIDGET
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

#endif
