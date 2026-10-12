import Foundation
import Security

// swiftlint:disable no_untyped_dictionaries - JSON trust boundary: builds Security framework queries, which take untyped dictionaries.

/// Stores the TypeSafe API key in macOS Keychain, outside preferences and classification files.
struct TypeSafeCredentials {
    private let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "ai.skillbox.typesafe",
        kSecAttrAccount as String: "api-key",
    ]

    private let copyMatching: ([String: Any]) -> (OSStatus, Data?)
    private let getInteraction: () -> (OSStatus, Bool)
    private let setInteraction: (Bool) -> OSStatus

    init(
        copyMatching: @escaping ([String: Any]) -> (OSStatus, Data?) = { query in
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)

            return (status, result as? Data)
        },
        getInteraction: @escaping () -> (OSStatus, Bool) = {
            var allowed: DarwinBoolean = false
            let status = SecKeychainGetUserInteractionAllowed(&allowed)

            return (status, allowed.boolValue)
        }, setInteraction: @escaping (Bool) -> OSStatus = { SecKeychainSetUserInteractionAllowed($0) }
    ) {
        self.copyMatching = copyMatching
        self.getInteraction = getInteraction
        self.setInteraction = setInteraction
    }

    /// File-based Keychains ignore modern per-query suppression (FB16959400); scope the legacy flag too.
    func readAPIKey(allowPrompt: Bool = false) throws -> String {
        var lookup = query

        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        lookup[kSecUseAuthenticationUI as String] = allowPrompt ? kSecUseAuthenticationUIAllow : kSecUseAuthenticationUIFail
        var priorInteraction: Bool?

        if !allowPrompt {
            let (status, prior) = getInteraction()

            guard status == errSecSuccess else { throw credentialsError(status) }
            let changed = setInteraction(false)

            guard changed == errSecSuccess else { throw credentialsError(changed) }
            priorInteraction = prior
        }

        defer { if let priorInteraction { _ = setInteraction(priorInteraction) } }
        let (status, data) = copyMatching(lookup)

        if status == errSecItemNotFound { return "" }

        guard status == errSecSuccess, let data,
            let key = String(data: data, encoding: .utf8)
        else {
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
        NSError(
            domain: "TypeSafeCredentials", code: Int(status),
            userInfo: [
                NSLocalizedDescriptionKey:
                    "TypeSafe key could not be accessed in Keychain: \(SecCopyErrorMessageString(status, nil) as String? ?? String(status))"
            ])
    }
}
