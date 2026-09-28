import UIKit

/// "Receptor 📤 💭": asks for a context the way the Shortcut did, then sends
/// `input $ context`. An empty context sends the input alone.
final class ContextViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        Task { @MainActor in
            let text = await ExtensionInput.text(from: extensionContext)
            guard !text.isEmpty else {
                extensionContext?.cancelRequest(withError: ShareCaptureError.emptyText)
                return
            }
            prompt(for: text)
        }
    }

    private func prompt(for text: String) {
        let alert = UIAlertController(title: "Enter your context", message: nil, preferredStyle: .alert)
        alert.addTextField { $0.autocapitalizationType = .sentences }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
        })
        alert.addAction(UIAlertAction(title: "Done", style: .default) { [weak self] _ in
            let context = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            ExtensionInput.capture(context.isEmpty ? text : "\(text) $ \(context)", source: "share-context", context: self?.extensionContext)
        })
        present(alert, animated: true)
    }
}
