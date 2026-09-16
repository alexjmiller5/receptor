import SwiftUI

struct ShareView: View {
    @State private var text: String
    @State private var context: String
    let onSend: (String) -> Void
    let onCancel: () -> Void

    init(initialText: String, onSend: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        _text = State(initialValue: initialText)
        _context = State(initialValue: Configuration.defaultContext(for: initialText) ?? "")
        self.onSend = onSend
        self.onCancel = onCancel
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedContext: String { context.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Thought") {
                    TextEditor(text: $text)
                        .frame(minHeight: 80)
                }
                Section {
                    TextField("Optional: project, category, date...", text: $context)
                        .autocorrectionDisabled()
                } header: {
                    Text("Context")
                } footer: {
                    Text("Sent as \"thought $ context\". Defaults per site live in Receptor's Settings.")
                }
            }
            .navigationTitle("Recept")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        onSend(trimmedContext.isEmpty ? trimmed : "\(trimmed) $ \(trimmedContext)")
                    }
                    .fontWeight(.semibold)
                    .disabled(trimmed.isEmpty)
                }
            }
        }
    }
}
