import Foundation

/// Settings and storage locations shared by the app and its extensions (share
/// sheet, widgets) through the App Group container.
enum Configuration {
    static let appGroupIdentifier = "group.com.alexmiller.receptor"
    static let urlScheme = "receptor"

    // Modal proxy credentials older builds stored; purged at launch.
    private static let legacyCredentialKeys = ["receptor_api_key", "receptor_proxy_secret"]
    private static let intakerURLKey = "receptor_intaker_url"
    private static let domainContextsKey = "receptor_domain_contexts"

    static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }

    static var sharedContainerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }

    static var storeURL: URL? {
        sharedContainerURL?.appendingPathComponent("Receptor.sqlite")
    }

    /// Directory for temporary upload payload files (background uploads need
    /// `fromFile:`); shared so the app can clean up an extension's upload.
    static var uploadsDirectory: URL? {
        guard let container = sharedContainerURL else { return nil }
        let dir = container.appendingPathComponent("uploads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func uploadFileURL(for thoughtId: UUID) -> URL? {
        uploadsDirectory?.appendingPathComponent("\(thoughtId.uuidString).json")
    }

    #if os(iOS)
    /// Earlier iOS builds (wildcard-signed, no App Group) kept settings in
    /// `UserDefaults.standard` and the store in Application Support. Same
    /// bundle id means the container survives the reinstall, so carry both
    /// over once; nothing is deleted so a rollback still has its data.
    static func migrateLegacyContainerIfNeeded() {
        guard let defaults = sharedDefaults, let container = sharedContainerURL else { return }
        let standard = UserDefaults.standard
        for key in [intakerURLKey] where defaults.string(forKey: key) == nil {
            if let legacy = standard.string(forKey: key) { defaults.set(legacy, forKey: key) }
        }
        guard let legacyDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
              let store = storeURL, !FileManager.default.fileExists(atPath: store.path) else { return }
        for suffix in ["", "-wal", "-shm"] {
            let src = legacyDir.appendingPathComponent("Receptor.sqlite\(suffix)")
            guard FileManager.default.fileExists(atPath: src.path) else { continue }
            try? FileManager.default.copyItem(at: src, to: container.appendingPathComponent("Receptor.sqlite\(suffix)"))
        }
    }
    #endif

    /// This device's own capture token (`Authorization: Bearer`), in the Keychain.
    static var captureToken: String? {
        get { TokenStore().load() }
        set {
            if let newValue, !newValue.isEmpty { TokenStore().save(newValue) } else { TokenStore().delete() }
        }
    }

    /// Builds stop holding the operator's Modal proxy credentials: a device
    /// authenticates only with the token its enrollment link gave it.
    static func purgeLegacyCredentials() {
        for defaults in [sharedDefaults, UserDefaults.standard].compactMap({ $0 }) {
            for key in legacyCredentialKeys { defaults.removeObject(forKey: key) }
        }
    }

    /// An enrollment link (`receptor://enroll?url=&token=`) sets both at once.
    static func enroll(url: URL, token: String) {
        intakerURL = url
        captureToken = token
    }

    /// A capture token as an enrollment link may carry it: 1-512 printable,
    /// whitespace-free characters.
    static func validToken(_ string: String) -> String? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 512,
              trimmed.unicodeScalars.allSatisfy({ $0.value > 0x20 && $0.value < 0x7F }) else { return nil }
        return trimmed
    }

    static var intakerURL: URL? {
        get {
            guard let urlString = sharedDefaults?.string(forKey: intakerURLKey) else {
                return nil
            }
            return URL(string: urlString)
        }
        set { sharedDefaults?.set(newValue?.absoluteString, forKey: intakerURLKey) }
    }

    static var isConfigured: Bool {
        intakerURL != nil && captureToken != nil
    }

    /// Only a complete http(s) URL with a host may be stored. Settings binds
    /// this to every keystroke, so a half-typed or momentarily cleared field must
    /// never replace a working URL (a nil URL silently rejects every capture).
    static func validIntakerURL(_ string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    /// `source` label for thoughts typed into this app's own compose sheet.
    static var appSource: String {
        #if os(iOS)
        "ios-app"
        #else
        "macos-app"
        #endif
    }

    /// "Pre-filled Receptor" contexts: host suffix -> context text appended as
    /// `$ context` when a shared link's host matches; the `*` key is the
    /// catch-all for everything else. User state, edited in Settings.
    static let catchAllDomain = "*"
    static var domainContexts: [String: String] {
        get {
            guard let data = sharedDefaults?.data(forKey: domainContextsKey),
                  let map = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
            return map
        }
        set {
            sharedDefaults?.set(try? JSONEncoder().encode(newValue), forKey: domainContextsKey)
        }
    }

    /// Default context for shared content: the rule whose host matches the
    /// content's first URL (a rule for `maps.app.goo.gl` also covers
    /// `www.maps.app.goo.gl`), else the catch-all, else nil.
    static func defaultContext(for text: String) -> String? {
        let rules = domainContexts
        guard !rules.isEmpty else { return nil }
        let hosts = text.split(whereSeparator: \.isWhitespace)
            .compactMap { URL(string: String($0))?.host?.lowercased() }
        for host in hosts {
            for (domain, context) in rules where domain != catchAllDomain {
                let d = domain.lowercased()
                if host == d || host.hasSuffix("." + d) { return context }
            }
        }
        if let all = rules[catchAllDomain], !all.isEmpty { return all }
        return nil
    }
}
