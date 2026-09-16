import AppIntents

/// Control Center / Action Button entry: opens the app straight into a new
/// thought. Lives in Shared so the widget extension and the app agree on it.
struct OpenComposeIntent: AppIntent {
    static let title: LocalizedStringResource = "New Thought"
    static let description = IntentDescription("Open Receptor to capture a thought")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        Configuration.pendingCompose = true
        return .result()
    }
}
