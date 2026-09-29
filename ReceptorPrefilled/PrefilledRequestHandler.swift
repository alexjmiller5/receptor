import Foundation

/// "Pre-filled Receptor 📤": appends the context configured for the link's
/// host in Receptor's Settings (`link $ context`), else the catch-all; with
/// neither it sends the link as-is. No screen of its own; a banner confirms.
final class PrefilledRequestHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        Task { @MainActor in
            let text = await ExtensionInput.text(from: context)
            let filled = Configuration.defaultContext(for: text).map { "\(text) $ \($0)" } ?? text
            await ExtensionInput.finish(filled, source: "share-prefilled", title: "Pre-filled Receptor 📤", context: context)
        }
    }
}
