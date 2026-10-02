import SwiftUI

/// Single switch for "show the compose sheet" so deep links and the toolbar
/// button open the same sheet, each stamping its own `source`.
@MainActor
final class ComposeRouter: ObservableObject {
    static let shared = ComposeRouter()
    @Published var showCompose = false
    /// `source` for the thought typed into the sheet that is open now.
    private(set) var composeSource = Configuration.appSource

    /// The in-app button passes nothing (`ios-app` / `macos-app`); a
    /// `receptor://compose` link passes its caller, else `ios-compose-link`.
    func openCompose(source: String = Configuration.appSource) {
        composeSource = source
        showCompose = true
    }

    func handle(_ url: URL) {
        guard let link = DeepLink.parse(url) else { return }
        switch link {
        case .compose(let source):
            openCompose(source: source ?? "ios-compose-link")
        case .recept(let text, let source):
            Task { await SyncManager.shared.queueThought(text, trigger: .deepLink, source: source) }
        }
    }
}
