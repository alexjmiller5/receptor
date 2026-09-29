import Foundation

/// "Pre-filled Receptor 📤": appends the context configured for the link's
/// host in Receptor's Settings (`link $ context`); no match sends it as-is.
final class PrefilledRequestHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        Task { @MainActor in
            let text = await ExtensionInput.text(from: context)
            let filled = Configuration.defaultContext(for: text).map { "\(text) $ \($0)" } ?? text
            ExtensionInput.capture(filled, source: "share-prefilled", title: "Pre-filled Receptor 📤", context: context)
        }
    }
}
