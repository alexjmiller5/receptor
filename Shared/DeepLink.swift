import Foundation

/// `receptor://compose` opens a new thought; `receptor://recept?text=...&source=...`
/// queues and sends one without UI (Hammerspoon, the agent skill, widgets).
enum DeepLink: Equatable {
    case compose
    case recept(text: String, source: String?)

    static let composeURL = URL(string: "receptor://compose")!

    static func parse(_ url: URL) -> DeepLink? {
        guard url.scheme?.lowercased() == Configuration.urlScheme else { return nil }
        switch url.host?.lowercased() {
        case "compose":
            return .compose
        case "recept":
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let text = items.first { $0.name == "text" }?.value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else { return nil }
            let source = items.first { $0.name == "source" }?.value
            return .recept(text: text, source: source?.isEmpty == false ? source : nil)
        default:
            return nil
        }
    }

    static func receptURL(text: String, source: String) -> URL {
        var c = URLComponents()
        c.scheme = Configuration.urlScheme
        c.host = "recept"
        c.queryItems = [URLQueryItem(name: "text", value: text), URLQueryItem(name: "source", value: source)]
        return c.url!
    }
}
