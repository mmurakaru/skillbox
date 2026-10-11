import Foundation

/// Uses the Grok CLI sign-in file; browser sign-ins and developer API keys are separate credentials.
struct GrokUsageCredentials: Sendable {
    let accessToken: String
    let email: String?
    let userID: String?

    static func load() throws -> GrokUsageCredentials {
        let home = ProcessInfo.processInfo.environment["GROK_HOME"] ?? "\(NSHomeDirectory())/.grok"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: "\(home)/auth.json")) else {
            throw UsageFetchError.unavailable("No Grok CLI sign-in found. Install the official Grok CLI using Connect Grok, run grok login, then refresh. Your grok.com browser sign-in is separate.")
        }
        return try decodeCredentials(data)
    }

    static func decodeCredentials(_ data: Data, now: Date = Date()) throws -> GrokUsageCredentials {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageFetchError.invalidResponse
        }
        let keys = json.keys.filter { $0.hasPrefix("https://auth.x.ai::") }.sorted()
            + json.keys.filter { $0 == "https://accounts.x.ai/sign-in" }.sorted()
        for key in keys {
            guard let entry = json[key] as? [String: Any], let token = entry["key"] as? String,
                  !token.isEmpty, !token.hasPrefix("xai-") else { continue }
            let expiry: Date?
            if let seconds = entry["expires_at"] as? Double {
                expiry = Date(timeIntervalSince1970: seconds)
            } else if let text = entry["expires_at"] as? String {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                expiry = formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
            } else { expiry = nil }
            guard let expiry, expiry > now else { continue }
            if entry["principal_type"] as? String == "team" {
                throw UsageFetchError.unavailable("Grok team usage is not available from the personal subscription endpoint.")
            }
            return GrokUsageCredentials(accessToken: token, email: entry["email"] as? String, userID: entry["user_id"] as? String)
        }
        throw UsageFetchError.unavailable("Grok sign-in is missing or expired. Run grok login, then refresh.")
    }
}
