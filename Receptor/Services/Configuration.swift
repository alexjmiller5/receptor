import Foundation

enum Configuration {
    static let appGroupIdentifier = "group.com.alexmiller.receptor"

    private static let apiKeyKey = "receptor_api_key"
    private static let intakerURLKey = "receptor_intaker_url"

    private static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }

    static var sharedContainerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }

    static var apiKey: String? {
        get { sharedDefaults?.string(forKey: apiKeyKey) }
        set { sharedDefaults?.set(newValue, forKey: apiKeyKey) }
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
        apiKey != nil && intakerURL != nil
    }
}
