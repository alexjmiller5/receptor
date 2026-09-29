import Foundation

/// "Receptor 📥": sends the shared link or text as-is. No screen of its own;
/// a banner confirms.
final class SendRequestHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        Task { @MainActor in
            await ExtensionInput.finish(await ExtensionInput.text(from: context), source: "share-send", title: "Receptor 📥", context: context)
        }
    }
}
