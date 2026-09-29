import UIKit

/// "Pre-filled Receptor 📤": appends the context configured for the link's
/// host in Receptor's Settings (`link $ context`), else the catch-all; with
/// neither it sends the link as-is. Then confirms.
final class PrefilledViewController: CaptureViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        Task { @MainActor in
            let text = await ExtensionInput.text(from: extensionContext)
            let filled = Configuration.defaultContext(for: text).map { "\(text) $ \($0)" } ?? text
            await capture(filled, source: "share-prefilled")
        }
    }
}
