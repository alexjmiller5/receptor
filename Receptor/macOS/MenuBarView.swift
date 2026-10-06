import SwiftUI

#if os(macOS)
import AppKit

/// macOS status-bar item. Left-click TOGGLES the real Receptor window (open if
/// closed, close if visible); right-click shows an Open/Quit menu. The item stays
/// in the menu bar for the app's whole lifetime — closing the window does NOT quit.
@MainActor
final class MacAppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var mainWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "brain.head.profile", accessibilityDescription: "Receptor"
        )
        item.button?.image?.isTemplate = true
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item

        // A Settings-only SwiftUI app does not forward openUntitledFile.
        // Default launches open the app; URL, login and service launches stay quiet.
        let launchReason = NSAppleEventManager.shared().currentAppleEvent?
            .paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue
        if notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool == true,
           launchReason != keyAELaunchedAsLogInItem,
           launchReason != keyAELaunchedAsServiceItem {
            showMainWindow()
        }
    }

    /// Menu-bar app: closing the window must NOT terminate the app, so the status
    /// item stays put and the window can be reopened from it.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// receptor:// links (Hammerspoon, the agent skill, enrollment links). Handled here rather than
    /// with .onOpenURL so neither link surfaces the main window: `compose` is
    /// the floating prompt, `recept` is silent.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let link = DeepLink.parse(url) else { continue }
            switch link {
            case .compose(let source):
                QuickCapturePanel.shared.show(source: source ?? "macos-panel")
            case .recept(let text, let source):
                Task { await SyncManager.shared.queueThought(text, trigger: .deepLink, source: source) }
            case .enroll(let url, let token):
                Configuration.enroll(url: url, token: token)
                SyncManager.shared.connectionChanged()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return false
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            toggleMainWindow()
        }
    }

    /// Left-click toggle: a visible window closes; an absent/hidden one opens.
    @objc private func toggleMainWindow() {
        if let win = mainWindow, win.isVisible {
            win.close()
        } else {
            showMainWindow()
        }
    }

    /// Create the main window lazily so background launches and captures cannot
    /// leave a window hidden beneath the foreground app.
    @objc private func showMainWindow() {
        if mainWindow == nil {
            guard let container = SyncManager.shared.modelContainer else { return }
            let content = MacContentView()
                .environmentObject(SyncManager.shared)
                .environmentObject(ComposeRouter.shared)
                .modelContainer(container)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 600),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false
            )
            window.title = "Receptor"
            window.identifier = NSUserInterfaceItemIdentifier("main")
            window.isReleasedWhenClosed = false
            window.isRestorable = false
            window.contentViewController = NSHostingController(rootView: content)
            window.setContentSize(NSSize(width: 500, height: 600))
            window.center()
            mainWindow = window
        }
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showMenu() {
        let menu = NSMenu()
        let open = NSMenuItem(
            title: "Open Receptor", action: #selector(showMainWindow), keyEquivalent: ""
        )
        open.target = self
        let quit = NSMenuItem(
            title: "Quit Receptor", action: #selector(quit), keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(open)
        menu.addItem(.separator())
        menu.addItem(quit)
        if let button = statusItem?.button {
            menu.popUp(
                positioning: nil,
                at: NSPoint(x: button.bounds.midX, y: button.bounds.maxY + 5),
                in: button
            )
        }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
#endif
