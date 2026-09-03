import Foundation
import Security

/// Persists the Navidrome login. Server URL and username live in
/// UserDefaults; the password goes to the login Keychain as a generic
/// password item so it never lands in a plain-text JSON file.
enum NavidromeAccountStore {
    private static let serverKey = "navidrome.serverURL"
    private static let userKey = "navidrome.username"
    private static let keychainService = "com.wamp.navidrome"

    static func load(defaults: UserDefaults = .standard) -> SubsonicCredentials? {
        guard let server = defaults.string(forKey: serverKey),
              let url = URL(string: server),
              let user = defaults.string(forKey: userKey), !user.isEmpty,
              let password = readPassword(account: user) else { return nil }
        return SubsonicCredentials(serverURL: url, username: user, password: password)
    }

    static func save(_ credentials: SubsonicCredentials, defaults: UserDefaults = .standard) {
        // A username change must not leave the old password item behind.
        if let old = defaults.string(forKey: userKey), old != credentials.username {
            deletePassword(account: old)
        }
        defaults.set(credentials.serverURL.absoluteString, forKey: serverKey)
        defaults.set(credentials.username, forKey: userKey)
        writePassword(credentials.password, account: credentials.username)
    }

    static func clear(defaults: UserDefaults = .standard) {
        if let user = defaults.string(forKey: userKey) {
            deletePassword(account: user)
        }
        defaults.removeObject(forKey: serverKey)
        defaults.removeObject(forKey: userKey)
    }

    /// Normalises what a user types into a server field: adds `http://` when
    /// no scheme is given, strips trailing slashes and a trailing `/rest`.
    static func normalizeServerURL(_ text: String) -> URL? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.contains("://") { s = "http://" + s }
        while s.hasSuffix("/") { s.removeLast() }
        if s.lowercased().hasSuffix("/rest") { s.removeLast(5) }
        guard let url = URL(string: s), url.host != nil else { return nil }
        return url
    }

    // MARK: - Keychain

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
        ]
    }

    private static func readPassword(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func writePassword(_ password: String, account: String) {
        let data = Data(password.utf8)
        let query = baseQuery(account: account)
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    private static func deletePassword(account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }
}
