import Foundation

/// "Receptor 📥": sends the shared link or text as-is. No screen of its own;
/// completion dismisses the share sheet.
final class SendRequestHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        Task { @MainActor in
            await ExtensionInput.finish(await ExtensionInput.text(from: context), source: "share-send", title: "Receptor 📥", context: context)
        }
    }
}
