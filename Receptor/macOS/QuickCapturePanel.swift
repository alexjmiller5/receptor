#if os(macOS)
import AppKit
import SwiftUI

/// A panel that takes the keyboard without activating its app, so the app the
/// user was in stays frontmost and gets focus back when the panel closes.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// `receptor://compose` on the Mac: a small floating prompt, centered, the way
/// the old "Receptor 💭" Shortcut asked for a thought - no main window, no app
/// activation (callers use `open -g`). Return sends (Shift+Return for a
/// newline), Escape cancels; a brief inline checkmark confirms local persistence, then the panel closes.
@MainActor
final class QuickCapturePanel {
    static let shared = QuickCapturePanel()
    private var panel: NSPanel?
    /// The caller named in the `receptor://compose` link (e.g. the hotkey).
    private var source = "macos-panel"

    func show(source: String) {
        self.source = source
        if let panel, panel.isVisible {
            panel.makeKeyAndOrderFront(nil)
            return
        }
        let host = NSHostingController(rootView: QuickCaptureView(
            onSend: { [weak self] text in await self?.send(text) ?? false },
            onCancel: { [weak self] in self?.close() }
        ))
        // .nonactivatingPanel only takes effect when set at init.
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 190),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.contentViewController = host
        panel.becomesKeyOnlyIfNeeded = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(button)?.isHidden = true
        }
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.setContentSize(NSSize(width: 460, height: 190))
        panel.center()
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
    }

    private func send(_ text: String) async -> Bool {
        await SyncManager.shared.queueThought(text, trigger: .captureIntent, source: source)
    }

    private func close() {
        panel?.orderOut(nil)
        panel = nil
    }
}

struct QuickCaptureView: View {
    let onSend: (String) async -> Bool
    let onCancel: () -> Void
    @State private var text = ""
    @State private var submitting = false
    @State private var feedback: String?
    @State private var saved = false
    @FocusState private var focused: Bool

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(feedback ?? "Enter your thought 💭")
                .font(.title3.weight(.semibold))
            if saved {
                VStack(spacing: 8) {
                    Label("Queued in Receptor", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, minHeight: 72)
            } else {
                TextEditor(text: $text)
                    .font(.body)
                    .focused($focused)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 72)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor)))
                    .onKeyPress(.return, phases: .down) { press in
                        if press.modifiers.contains(.shift) { return .ignored }
                        if !trimmed.isEmpty { submit() }
                        return .handled
                    }
                    .onKeyPress(.escape) { onCancel(); return .handled }
            }
            HStack {
                Text("Return sends · Shift+Return for a new line")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Done") { submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmed.isEmpty || submitting)
            }
        }
        // The panel has a hidden, full-size title bar: without ignoring its
        // safe area the content starts a title bar's height too low. Top
        // padding equals the gap under the heading.
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .frame(width: 460)
        .ignoresSafeArea()
        .onAppear { focused = true }
        .disabled(submitting)
    }
    private func submit() {
        guard !submitting else { return }
        submitting = true
        Task { @MainActor in
            saved = await onSend(trimmed)
            if saved {
                focused = false
                feedback = "Saved"
                try? await Task.sleep(for: .milliseconds(2100))
                onCancel()
            } else {
                feedback = "Could not save. Try again."
                submitting = false
            }
        }
    }

}
#endif
