import Foundation
import Security

/// Claude usage reads suppress Keychain ACL dialogs except after an explicit Connect action.
struct ClaudeUsageCredentials {
    struct ReadResult {
        enum Source { case file, keychain }
        let values: [String: Any]
        let source: Source
    }

    static func loadCredentials(
        configuredHome: String? = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"],
        defaultHome: String = "\(NSHomeDirectory())/.claude",
        allowPrompt: Bool,
        keychainReader: (Bool) throws -> [String: Any] = ClaudeUsageCredentials.readKeychainCredentials
    ) throws -> [String: Any] {
        try readCredentials(configuredHome: configuredHome, defaultHome: defaultHome, allowPrompt: allowPrompt, keychainReader: keychainReader).values
    }

    /// Automatic refresh reads only credential files. Foreign Keychain access requires Connect.
    static func readCredentials(
        configuredHome: String? = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"],
        defaultHome: String = "\(NSHomeDirectory())/.claude",
        allowPrompt: Bool,
        keychainReader: (Bool) throws -> [String: Any] = ClaudeUsageCredentials.readKeychainCredentials
    ) throws -> ReadResult {
        let home = configuredHome ?? defaultHome
        if FileManager.default.fileExists(atPath: "\(home)/.credentials.json") {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: "\(home)/.credentials.json")),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw UsageFetchError.unavailable("Claude Code credentials file could not be read. Sign in with Claude Code again.")
            }
            return .init(values: json, source: .file)
        }
        guard configuredHome == nil else {
            throw UsageFetchError.unavailable("Sign in with Claude Code in your configured profile, then refresh.")
        }
        guard allowPrompt else {
            throw UsageFetchError.claudeKeychainPermissionRequired
        }
        return .init(values: try keychainReader(true), source: .keychain)
    }

    /// Used only by explicit connection; automatic refresh never queries the foreign Keychain.
    static func keychainQuery(allowPrompt: Bool) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationUI as String: allowPrompt ? kSecUseAuthenticationUIAllow : kSecUseAuthenticationUIFail,
        ]
    }

    static func readKeychainCredentials(allowPrompt: Bool) throws -> [String: Any] {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(keychainQuery(allowPrompt: allowPrompt) as CFDictionary, &result)
        switch status {
        case errSecSuccess: break
        case errSecItemNotFound:
            throw UsageFetchError.unavailable("No Claude Code sign-in found. Sign in with Claude Code, then connect.")
        case errSecInteractionNotAllowed, errSecAuthFailed, errSecUserCanceled:
            throw UsageFetchError.unavailable("Claude Code credentials need Keychain permission. Click Connect Claude Code to grant access. Background refresh will not prompt.")
        default:
            throw UsageFetchError.unavailable("Claude Code Keychain access failed (\(status)). Click Connect Claude Code to retry.")
        }
        guard let data = result as? Data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageFetchError.unavailable("Claude Code credentials could not be decoded. Sign in with Claude Code again.")
        }
        return json
    }
}
