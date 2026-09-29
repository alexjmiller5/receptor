import Foundation
import UniformTypeIdentifiers
import UserNotifications

/// What the share sheet handed an extension: the first URL (Safari shares a
/// URL plus its title), else the plain text.
enum ExtensionInput {
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

    /// Queue `text`, confirm with a self-dismissing banner showing what was
    /// sent (the extension has no other way to give feedback), finish the
    /// request; an empty input is a cancel.
    @MainActor
    static func capture(_ text: String, source: String, title: String, context: NSExtensionContext?) {
        do {
            try ShareCapture.enqueue(text: text, source: source, container: try ShareCapture.makeContainer())
            let content = UNMutableNotificationContent()
            content.title = "\(title) ✓"
            content.body = String(text.prefix(200))
            content.sound = nil
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)) { _ in
                context?.completeRequest(returningItems: nil)
            }
        } catch {
            context?.cancelRequest(withError: error)
        }
    }
}
