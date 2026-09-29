import Foundation

/// "Receptor 📥": sends the shared link or text as-is, no UI.
final class SendRequestHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        Task { @MainActor in
            let text = await ExtensionInput.text(from: context)
            await ExtensionInput.capture(text, source: "share-send", title: "Receptor 📥", context: context)
        }
    }
}
