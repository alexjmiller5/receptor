import SwiftUI

/// Single switch for "show the compose sheet" so widgets, deep links, the
/// Control Center button and the toolbar all open the same sheet.
@MainActor
final class ComposeRouter: ObservableObject {
    static let shared = ComposeRouter()
    @Published var showCompose = false

    func handle(_ url: URL) {
        guard let link = DeepLink.parse(url) else { return }
        switch link {
        case .compose:
            showCompose = true
        case .recept(let text, let source):
            Task { await SyncManager.shared.queueThought(text, trigger: .deepLink, source: source) }
        }
    }
}
