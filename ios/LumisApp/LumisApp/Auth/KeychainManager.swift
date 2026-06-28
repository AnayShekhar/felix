import Foundation
import Security

/// Thin wrapper over the iOS Keychain for the auth token and cached user.
/// Tokens are NEVER stored in UserDefaults.
enum KeychainManager {
    static let tokenKey = "lumis.auth.token"
    static let userKey  = "lumis.auth.user"

    @discardableResult
    static func save(_ data: Data, for key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        // Update if present, otherwise add.
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert.merge(attributes) { _, new in new }
            return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }

    static func load(_ key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else {
            return nil
        }
        return result as? Data
    }

    @discardableResult
    static func delete(_ key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - Typed convenience

    static var token: String? {
        get { load(tokenKey).flatMap { String(data: $0, encoding: .utf8) } }
        set {
            if let newValue, let data = newValue.data(using: .utf8) {
                save(data, for: tokenKey)
            } else {
                delete(tokenKey)
            }
        }
    }

    static func saveUser(_ user: LumisUser) {
        if let data = try? JSONEncoder().encode(user) { save(data, for: userKey) }
    }

    static func loadUser() -> LumisUser? {
        load(userKey).flatMap { try? JSONDecoder().decode(LumisUser.self, from: $0) }
    }

    static func clear() {
        delete(tokenKey)
        delete(userKey)
    }
}
