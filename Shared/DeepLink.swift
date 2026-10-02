import Foundation

/// `receptor://compose?source=...` opens a new thought; `receptor://recept?text=...&source=...`
/// queues and sends one without UI (Hammerspoon, the agent skill). `source` names
/// the caller (which hotkey, button or agent) and is logged on the Synapse execution.
/// `receptor://enroll?url=...&token=...` connects this device (from an enrollment link).
enum DeepLink: Equatable {
    case compose(source: String?)
    case recept(text: String, source: String?)
    /// From an enrollment link: the capture endpoint and this device's token.
    case enroll(url: URL, token: String)

    static func parse(_ url: URL) -> DeepLink? {
        guard url.scheme?.lowercased() == Configuration.urlScheme else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let rawSource = items.first { $0.name == "source" }?.value
        let source = rawSource?.isEmpty == false ? rawSource : nil
        switch url.host?.lowercased() {
        case "compose":
            return .compose(source: source)
        case "recept":
            let text = items.first { $0.name == "text" }?.value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else { return nil }
            return .recept(text: text, source: source)
        case "enroll":
            guard let url = items.first(where: { $0.name == "url" })?.value.flatMap(Configuration.validIntakerURL),
                  let token = items.first(where: { $0.name == "token" })?.value.flatMap(Configuration.validToken)
            else { return nil }
            return .enroll(url: url, token: token)
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
