import UIKit
import SwiftUI

/// "Receptor 📤 💭": asks for a context, then sends `input $ context`; an
/// empty context sends the input alone. A banner confirms.
final class ContextViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        Task { @MainActor in
            let text = await ExtensionInput.text(from: extensionContext)
            guard !text.isEmpty else {
                extensionContext?.cancelRequest(withError: ShareCaptureError.emptyText)
                return
            }
            let host = UIHostingController(rootView: ContextPrompt(
                shared: text,
                onDone: { [weak self] context in
                    Task { @MainActor in
                        await ExtensionInput.finish(context.isEmpty ? text : "\(text) $ \(context)", source: "share-context", title: "Receptor 📤 💭", context: self?.extensionContext)
                    }
                },
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
    }
}

/// iOS presents this extension in its own full-height sheet, so the prompt is
/// laid out as a proper sheet: bar on top, the context field right under it,
/// what is being shared below, keyboard up.
struct ContextPrompt: View {
    let shared: String
    let onDone: (String) -> Void
    let onCancel: () -> Void
    @State private var context = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Enter your context") {
                    TextField("Context", text: $context, axis: .vertical)
                        .lineLimit(2...6)
                        .focused($focused)
                }
                Section("Sharing") {
                    Text(shared)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
            .navigationTitle("Receptor 📤 💭")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onDone(context.trimmingCharacters(in: .whitespacesAndNewlines)) }
                        .fontWeight(.semibold)
                }
            }
        }
        .onAppear { focused = true }
    }
}
