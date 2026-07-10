import SwiftUI
import AppKit

#if os(macOS)
/// Bridges the AppKit status-item click to SwiftUI's `openWindow`, which can open
/// the "main" Window scene even after it's been closed. The closure is captured
/// once from a live SwiftUI view (the main window's content) and reused.
final class MenuBarCoordinator: ObservableObject {
    static let shared = MenuBarCoordinator()
    var openMainWindow: (() -> Void)?
}

/// macOS status-bar item. Left-click opens the real Receptor window (same as the
/// old "Open Receptor" / ⌘O did); right-click shows a small Open/Quit menu so the
/// app can still be quit from the menu bar (it's an accessory app, no Dock icon).
final class MacAppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

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
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            openMainWindow()
        }
    }

    @objc private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let win = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) {
            win.makeKeyAndOrderFront(nil)
        } else {
            MenuBarCoordinator.shared.openMainWindow?()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        let open = NSMenuItem(
            title: "Open Receptor", action: #selector(openMainWindow), keyEquivalent: ""
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
