import Foundation

#if os(macOS)
import ServiceManagement

@MainActor
final class LoginItemManager: ObservableObject {
    static let shared = LoginItemManager()

    @Published private(set) var isEnabled: Bool = false

    private init() {
        updateStatus()
    }

    func updateStatus() {
        if #available(macOS 13.0, *) {
            isEnabled = SMAppService.mainApp.status == .enabled
        } else {
            isEnabled = false
        }
    }

    func setEnabled(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                updateStatus()
            } catch {
                print("Failed to \(enabled ? "enable" : "disable") login item: \(error)")
            }
        }
    }

    func toggle() {
        setEnabled(!isEnabled)
    }
}
#endif
