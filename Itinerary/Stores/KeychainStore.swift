import Foundation
import Security

/// Minimal wrapper around generic password items in the iOS Keychain.
enum KeychainStore {
    private static let service = (Bundle.main.bundleIdentifier ?? "Itinerary") + ".secrets"

    static func string(for account: String) -> String? {
        var query = baseQuery(for: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Stores the value, or deletes the item when the value is `nil` or empty.
    static func set(_ value: String?, for account: String) {
        SecItemDelete(baseQuery(for: account) as CFDictionary)
        guard let value, !value.isEmpty else { return }
        var query = baseQuery(for: account)
        query[kSecValueData as String] = Data(value.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func baseQuery(for account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

extension KeychainStore {
    /// API key of a provider with surrounding whitespace removed, or `nil` when missing.
    static func apiKey(for provider: LLMProvider) -> String? {
        let key = string(for: provider.keychainAccount)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return key.isEmpty ? nil : key
    }
}
