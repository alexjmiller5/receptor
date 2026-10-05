import Foundation
import UniformTypeIdentifiers
import UserNotifications

/// What the share sheet handed an extension, and how an extension finishes.
enum ExtensionInput {
    /// The first URL (Safari shares a URL plus its title), else the plain text.
    static func text(from context: NSExtensionContext?) async -> String {
        let providers = (context?.inputItems as? [NSExtensionItem])?
            .flatMap { $0.attachments ?? [] } ?? []
        for type in [UTType.url, UTType.plainText] {
            for provider in providers where provider.hasItemConformingToTypeIdentifier(type.identifier) {
                if let item = try? await provider.loadItem(forTypeIdentifier: type.identifier) {
                    if let url = item as? URL { return url.absoluteString }
                    if let text = item as? String { return text }
                    if let data = item as? Data, let text = String(data: data, encoding: .utf8) { return text }
                }
            }
        }
        return ""
    }

    /// Only failures need a notification. UI-bearing callers can briefly
    /// confirm inline before the extension completes.
    @MainActor
    static func finish(_ text: String, source: String, title: String, context: NSExtensionContext?,
                       onCaptured: ((ShareCapture.Outcome) async -> Void)? = nil) async {
        do {
            let outcome = try await ShareCapture.capture(text: text, source: source, container: try ShareCapture.makeContainer())
            let failure: String?
            switch outcome {
            case .sent: failure = nil
            case .queued: failure = Configuration.isConfigured ? nil : "Not connected. Open an enrollment link in Receptor."
            case .unauthorized: failure = "Access refused. Open a new enrollment link in Receptor."
            case .rejected(let code): failure = "Rejected (HTTP \(code)). Not retried."
            }
            if let failure { await notifyFailure(title: title, message: failure + "\n" + String(text.prefix(200))) }
            await onCaptured?(outcome)
            context?.completeRequest(returningItems: nil)
        } catch {
            await notifyFailure(title: title, message: error.localizedDescription)
            context?.cancelRequest(withError: error)
        }
    }

    private static func notifyFailure(title: String, message: String) async {
        let content = UNMutableNotificationContent()
        content.title = title + " - capture needs attention"
        content.body = message
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
