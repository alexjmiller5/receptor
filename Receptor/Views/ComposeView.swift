import SwiftUI

struct ComposeView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var syncManager: SyncManager
    @State private var text = ""
    @FocusState private var isFocused: Bool

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        #if os(macOS)
        macOSCompose
        #else
        iOSCompose
        #endif
    }

    #if os(iOS)
    private var iOSCompose: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextEditor(text: $text)
                    .focused($isFocused)
                    .padding()
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty {
                            Text("What's on your mind?")
                                .foregroundStyle(.tertiary)
                                .padding(.leading, 20)
                                .padding(.top, 24)
                                .allowsHitTesting(false)
                        }
                    }

                Divider()

                syntaxHints
            }
            .navigationTitle("New Thought")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") { send() }
                        .fontWeight(.semibold)
                        .disabled(trimmedText.isEmpty)
                }
            }
            .onAppear { isFocused = true }
        }
    }
    #endif

    #if os(macOS)
    private var macOSCompose: some View {
        VStack(spacing: 12) {
            Text("New Thought")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            TextEditor(text: $text)
                .focused($isFocused)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("What's on your mind?")
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 13)
                            .padding(.top, 9)
                            .allowsHitTesting(false)
                    }
                }

            HStack(spacing: 8) {
                syntaxHints

                Spacer()

                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button("Send") { send() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedText.isEmpty)
            }
        }
        .padding(16)
        .frame(minWidth: 400, minHeight: 250)
        .onAppear { isFocused = true }
    }
    #endif

    private var syntaxHints: some View {
        HStack(spacing: 8) {
            SyntaxHint(symbol: "@", description: "Split items")
            SyntaxHint(symbol: "$", description: "Add context")
        }
    }

    private func send() {
        Task {
            await syncManager.queueThought(trimmedText, trigger: .composeButton)
            dismiss()
        }
    }
}

struct SyntaxHint: View {
    let symbol: String
    let description: String

    var body: some View {
        HStack(spacing: 6) {
            Text(symbol)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.bold)
                .foregroundStyle(.blue)
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.blue.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

#Preview {
    ComposeView()
}
