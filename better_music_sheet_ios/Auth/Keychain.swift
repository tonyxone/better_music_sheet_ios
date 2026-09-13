import Foundation
import Security

/// Minimal string store. Used for the guest id and the backend session, both
/// of which must survive app restarts; the Keychain also keeps them out of
/// backups-as-plaintext without any extra work.
nonisolated enum Keychain {
    static func string(for key: String) -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func set(_ value: String?, for key: String) -> Bool {
        guard let value else { return delete(key) }
        let data = Data(value.utf8)
        let query = baseQuery(for: key)

        let attributes: [String: Any] = [kSecValueData as String: data]
        let updated = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updated == errSecSuccess { return true }
        guard updated == errSecItemNotFound else { return false }

        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    static func delete(_ key: String) -> Bool {
        let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private static func baseQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.bettermusicsheet.ios",
            kSecAttrAccount as String: key,
        ]
    }
}
