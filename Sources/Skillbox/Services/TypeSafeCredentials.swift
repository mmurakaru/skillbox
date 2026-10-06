import Foundation
import Security

/// Stores the TypeSafe API key in macOS Keychain, outside preferences and classification files.
struct TypeSafeCredentials {
    private let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "ai.skillbox.typesafe",
        kSecAttrAccount as String: "api-key",
    ]

    func readAPIKey() throws -> String {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            throw credentialsError(status)
        }
        return key
    }

    func saveAPIKey(_ key: String) throws {
        if key.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw credentialsError(status)
            }
            return
        }
        let values = [kSecValueData as String: Data(key.utf8)]
        let status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item.merge(values) { _, new in new }
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw credentialsError(added) }
        } else if status != errSecSuccess {
            throw credentialsError(status)
        }
    }

    private func credentialsError(_ status: OSStatus) -> NSError {
        NSError(domain: "TypeSafeCredentials", code: Int(status), userInfo: [
            NSLocalizedDescriptionKey: "TypeSafe key could not be accessed in Keychain: \(SecCopyErrorMessageString(status, nil) as String? ?? String(status))",
        ])
    }
}
