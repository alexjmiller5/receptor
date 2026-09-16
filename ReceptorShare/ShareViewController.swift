import UIKit
import SwiftUI
import UniformTypeIdentifiers

/// Share-sheet entry: shows the shared text/URL with an optional context, then
/// queues it through ShareCapture and hands the upload to the OS.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        Task { await present(initialText: await sharedText()) }
    }

    private func present(initialText: String) {
        let host = UIHostingController(rootView: ShareView(
            initialText: initialText,
            onSend: { [weak self] text in self?.send(text) },
            onCancel: { [weak self] in
                self?.extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
            }
        ))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    private func send(_ text: String) {
        do {
            let container = try ShareCapture.makeContainer()
            try ShareCapture.enqueue(text: text, container: container)
            extensionContext?.completeRequest(returningItems: nil)
        } catch {
            let alert = UIAlertController(title: "Could not queue", message: error.localizedDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
                self?.extensionContext?.cancelRequest(withError: error)
            })
            present(alert, animated: true)
        }
    }

    /// URL first (Safari shares both a URL and its title), else plain text.
    private func sharedText() async -> String {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem])?
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
}
