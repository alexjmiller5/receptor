import UIKit

/// "Receptor 📥": sends the shared link or text as-is, then confirms.
final class SendViewController: CaptureViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        Task { @MainActor in
            await capture(await ExtensionInput.text(from: extensionContext), source: "share-send")
        }
    }
}
