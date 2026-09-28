import UIKit
import SwiftUI

/// "Receptor 📤 💭": asks for a context the way the Shortcut's "Ask for Input"
/// did - a card at the bottom with the prompt, a text field and Done - then
/// sends `input $ context`. An empty context sends the input alone.
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
            let host = UIHostingController(rootView: ContextPromptCard(
                onDone: { [weak self] context in
                    ExtensionInput.capture(context.isEmpty ? text : "\(text) $ \(context)", source: "share-context", context: self?.extensionContext)
                },
                onCancel: { [weak self] in
                    self?.extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
                }
            ))
            host.view.backgroundColor = .clear
            addChild(host)
            host.view.frame = view.bounds
            host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(host.view)
            host.didMove(toParent: self)
        }
    }
}

struct ContextPromptCard: View {
    let onDone: (String) -> Void
    let onCancel: () -> Void
    @State private var context = ""
    @FocusState private var focused: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.35).ignoresSafeArea().onTapGesture(perform: onCancel)
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Button("Cancel", action: onCancel)
                    Spacer()
                    Text("Receptor").font(.headline)
                    Spacer()
                    Button("Done") { onDone(context.trimmingCharacters(in: .whitespacesAndNewlines)) }
                        .fontWeight(.semibold)
                }
                Text("Enter your context")
                    .font(.title3.weight(.semibold))
                TextField("Context", text: $context, axis: .vertical)
                    .lineLimit(3...6)
                    .focused($focused)
                    .padding(12)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                    .submitLabel(.done)
                    .onSubmit { onDone(context.trimmingCharacters(in: .whitespacesAndNewlines)) }
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28))
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .onAppear { focused = true }
    }
}
