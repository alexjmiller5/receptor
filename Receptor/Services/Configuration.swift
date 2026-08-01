import Foundation

enum Configuration {
    static let appGroupIdentifier = "group.com.alexmiller.receptor"

    // apiKey now holds the Modal proxy token ID (sent as the Modal-Key header);
    // storage key unchanged so existing installs don't lose their value slot.
    private static let apiKeyKey = "receptor_api_key"
    private static let proxySecretKey = "receptor_proxy_secret"
    private static let intakerURLKey = "receptor_intaker_url"

    // iOS builds are signed with the wildcard Ad Hoc profile, which cannot carry
    // an App Groups entitlement — so iOS stores everything in the app's own
    // container. macOS keeps the group container (existing data lives there).
    private static var sharedDefaults: UserDefaults? {
        #if os(iOS)
        .standard
        #else
        UserDefaults(suiteName: appGroupIdentifier)
        #endif
    }

    static var sharedContainerURL: URL? {
        #if os(iOS)
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
        #else
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
        #endif
    }

    static var apiKey: String? {
        get { sharedDefaults?.string(forKey: apiKeyKey) }
        set { sharedDefaults?.set(newValue, forKey: apiKeyKey) }
    }

    static var proxySecret: String? {
        get { sharedDefaults?.string(forKey: proxySecretKey) }
        set { sharedDefaults?.set(newValue, forKey: proxySecretKey) }
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
        apiKey != nil && proxySecret != nil && intakerURL != nil
    }
}
