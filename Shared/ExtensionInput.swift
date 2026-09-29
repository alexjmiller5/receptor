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

    /// Send `text`, confirm, finish the request. The confirmation is a
    /// notification banner: iOS gives any extension that shows its own view a
    /// full-height opaque sheet, so a banner is the only feedback that does
    /// not cover the page the user is sharing from.
    @MainActor
    static func finish(_ text: String, source: String, title: String, context: NSExtensionContext?) async {
        do {
            let outcome = try await ShareCapture.capture(text: text, source: source, container: try ShareCapture.makeContainer())
            let content = UNMutableNotificationContent()
            switch outcome {
            case .sent: content.title = "\(title) ✓"
            case .queued: content.title = "\(title) - queued, sends on the next sync"
            case .rejected(let code): content.title = "\(title) - rejected (HTTP \(code))"
            }
            content.body = String(text.prefix(200))
            do {
                try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
                DebugFileLog.write("[SHARE] banner posted")
            } catch {
                DebugFileLog.write("[SHARE] banner failed: \(error.localizedDescription)")
            }
            context?.completeRequest(returningItems: nil)
        } catch {
            context?.cancelRequest(withError: error)
        }
    }
}
