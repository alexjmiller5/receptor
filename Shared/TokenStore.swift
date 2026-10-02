import Foundation
import Security

/// The device's capture token (issued by the capture service through an
/// enrollment link) lives in the Keychain, never in UserDefaults. On iOS the
/// item sits in the App Group's access group so the share extensions can read it.
struct TokenStore {
    var service = "com.alexmiller.receptor.capture-token"

    private var query: [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "capture",
        ]
        #if os(iOS)
        query[kSecAttrAccessGroup as String] = Configuration.appGroupIdentifier
        #endif
        return query
    }

    func load() -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &value) == errSecSuccess,
              let data = value as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    func save(_ token: String) -> Bool {
        var values: [String: Any] = [kSecValueData as String: Data(token.utf8)]
        #if os(iOS)
        // Background uploads and share extensions run while the phone is locked.
        values[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        #endif
        var status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(values) { _, new in new } as CFDictionary, nil)
        }
        return status == errSecSuccess
    }

    func delete() {
        SecItemDelete(query as CFDictionary)
    }
}
