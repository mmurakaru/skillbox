import Foundation

// swiftlint:disable no_untyped_dictionaries - JSON trust boundary: parses token and profile payloads owned by providers.

/// Account identity is read from the same credential snapshot used for that provider's usage request.
struct ProviderUsageIdentity {
    static func codexEmail(from token: String?) -> String? {
        guard let token else { return nil }
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)

        guard parts.count == 3 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")

        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        // This decodes display identity only. The provider authenticates the unchanged access token.
        return json["email"] as? String
    }

    static func claudeEmail(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let account = json["account"] as? [String: Any] ?? json

        return account["email"] as? String ?? account["email_address"] as? String ?? account["emailAddress"] as? String
    }

    static func planLabel(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        switch raw.lowercased() {
        case "prolite", "pro_lite": return "Pro Lite"
        case "supergrok", "super_grok": return "SuperGrok"
        case "supergrokheavy", "super_grok_heavy", "supergrok_heavy": return "SuperGrok Heavy"
        default: return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}
