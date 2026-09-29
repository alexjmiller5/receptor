#if os(macOS)
import AppKit
import SwiftUI
import UserNotifications

/// `receptor://compose` on the Mac: a small floating prompt, centered, the way
/// the old "Receptor 💭" Shortcut asked for a thought - no main window. Return
/// sends (Shift+Return for a newline), Escape cancels; the panel closes itself
/// and a banner confirms what was sent.
@MainActor
final class QuickCapturePanel {
    static let shared = QuickCapturePanel()
    private var panel: NSPanel?

    func show() {
        if let panel, panel.isVisible {
            panel.makeKeyAndOrderFront(nil)
            return
        }
        let host = NSHostingController(rootView: QuickCaptureView(
            onSend: { [weak self] text in self?.send(text) },
            onCancel: { [weak self] in self?.close() }
        ))
        let panel = NSPanel(contentViewController: host)
        panel.styleMask = [.titled, .fullSizeContentView, .nonactivatingPanel]
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

    private func send(_ text: String) {
        close()
        Task {
            // .captureIntent keeps SyncManager's own "Synced N" banner quiet;
            // this banner carries the text instead, like the share-sheet actions.
            await SyncManager.shared.queueThought(text, trigger: .captureIntent, source: Configuration.appSource)
            let content = UNMutableNotificationContent()
            content.title = "Receptor 💭 ✓"
            content.body = String(text.prefix(200))
            try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }

    private func close() {
        panel?.orderOut(nil)
        panel = nil
    }
}

struct QuickCaptureView: View {
    let onSend: (String) -> Void
    let onCancel: () -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Enter your thought 💭")
                .font(.title3.weight(.semibold))
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
                    if !trimmed.isEmpty { onSend(trimmed) }
                    return .handled
                }
                .onKeyPress(.escape) { onCancel(); return .handled }
            HStack {
                Text("Return sends · Shift+Return for a new line")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Done") { onSend(trimmed) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmed.isEmpty)
            }
        }
        .padding(16)
        .frame(width: 460)
        .onAppear { focused = true }
    }
}
#endif
