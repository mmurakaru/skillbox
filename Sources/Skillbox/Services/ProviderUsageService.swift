import Foundation
import Security

/// Fetches subscription usage without refreshing or writing provider-owned credentials.
protocol ProviderUsageFetching: Sendable {
    func fetchUsage(for provider: UsageProvider, allowKeychainPrompt: Bool) async throws -> ProviderUsageSnapshot
}

/// Reads existing CLI sign-ins and sends credentials only to the matching provider endpoint.
actor ProviderUsageService: ProviderUsageFetching {
    private var cachedClaudeCredentials: [String: Any]?
    private let session: URLSession
    private let claudeCLIReader: (@Sendable () async throws -> ProviderUsageSnapshot?)?
    private let claudeCredentialsReader: @Sendable (Bool) throws -> [String: Any]
    private let grokCredentialsReader: @Sendable () throws -> GrokUsageCredentials
    init(session: URLSession? = nil,
         claudeCLIReader: (@Sendable () async throws -> ProviderUsageSnapshot?)? = { try await ClaudeCLIUsageReader.fetchInstalledCLIUsage() },
         claudeCredentialsReader: @escaping @Sendable (Bool) throws -> [String: Any] = { try ClaudeUsageCredentials.loadCredentials(allowPrompt: $0) },
         grokCredentialsReader: @escaping @Sendable () throws -> GrokUsageCredentials = { try GrokUsageCredentials.load() }) {
        self.claudeCredentialsReader = claudeCredentialsReader
        self.grokCredentialsReader = grokCredentialsReader
        self.claudeCLIReader = claudeCLIReader
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        self.session = session ?? URLSession(configuration: configuration)
    }

    func fetchUsage(for provider: UsageProvider, allowKeychainPrompt: Bool = false) async throws -> ProviderUsageSnapshot {
        if provider == .claude, let claudeCLIReader, let snapshot = try await claudeCLIReader() {
            return snapshot
        }
        let credentials: [String: Any]
        let token: String
        var accountEmail: String?
        var request: URLRequest
        switch provider {
        case .grok:
            let grok = try grokCredentialsReader()
            credentials = [:]
            token = grok.accessToken
            accountEmail = grok.email
            request = URLRequest(url: URL(string: "https://cli-chat-proxy.grok.com/v1/billing?format=credits")!)
            request.setValue("xai-grok-cli", forHTTPHeaderField: "x-xai-token-auth")
            if let userID = grok.userID { request.setValue(userID, forHTTPHeaderField: "x-userid") }
        case .codex:
            let home = ProcessInfo.processInfo.environment["CODEX_HOME"] ?? "\(NSHomeDirectory())/.codex"
            credentials = try readCredentials(at: "\(home)/auth.json", provider: provider)
            guard let tokens = credentials["tokens"] as? [String: Any],
                  let accessToken = tokens["access_token"] as? String, !accessToken.isEmpty else {
                throw UsageFetchError.unavailable("Sign in with Codex to read subscription usage. API keys do not report plan limits.")
            }
            token = accessToken
            accountEmail = ProviderUsageIdentity.codexEmail(from: tokens["id_token"] as? String)
            request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
            if let accountID = tokens["account_id"] as? String, !accountID.isEmpty {
                request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
            }
            request.setValue("codex-cli", forHTTPHeaderField: "User-Agent")
        case .claude:
            if !allowKeychainPrompt, let cachedClaudeCredentials {
                credentials = cachedClaudeCredentials
            } else {
                credentials = try claudeCredentialsReader(allowKeychainPrompt)
            }
            guard let oauth = credentials["claudeAiOauth"] as? [String: Any],
                  let accessToken = oauth["accessToken"] as? String, !accessToken.isEmpty else {
                throw UsageFetchError.unavailable("Sign in with Claude Code, then refresh usage.")
            }
            token = accessToken
            request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
            request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        }
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw UsageFetchError.invalidResponse }
        switch response.statusCode {
        case 200: break
        case 401, 403:
            if provider == .claude { cachedClaudeCredentials = nil }
            throw UsageFetchError.unavailable("Usage access was rejected. Sign in with \(provider.name) again, then refresh.")
        case 429:
            throw UsageFetchError.unavailable("Too many usage requests. Try refreshing later.")
        default:
            throw UsageFetchError.unavailable("\(provider.name) usage is unavailable (HTTP \(response.statusCode)).")
        }
        var snapshot = try Self.decodeUsage(data, provider: provider)
        if provider == .grok {
            // Grok's CLI enriches billing with the plan from /settings. Keep the captured account headers.
            var settingsRequest = request
            settingsRequest.url = URL(string: "https://cli-chat-proxy.grok.com/v1/settings")!
            settingsRequest.timeoutInterval = 5
            if let (settingsData, settingsResponse) = try? await session.data(for: settingsRequest),
               (settingsResponse as? HTTPURLResponse)?.statusCode == 200,
               let settings = try? JSONSerialization.jsonObject(with: settingsData) as? [String: Any] {
                snapshot.plan = ProviderUsageIdentity.planLabel(settings["subscription_tier_display"] as? String
                    ?? settings["subscription_tier"] as? String) ?? snapshot.plan
            }
        }
        if provider == .claude, let oauth = credentials["claudeAiOauth"] as? [String: Any] {
            cachedClaudeCredentials = credentials
            snapshot.plan = ProviderUsageIdentity.planLabel(oauth["subscriptionType"] as? String)
            // Profile and usage use the same captured token even if the CLI switches accounts mid-request.
            var profileRequest = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/profile")!)
            profileRequest.timeoutInterval = 5
            profileRequest.cachePolicy = .reloadIgnoringLocalCacheData
            profileRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            profileRequest.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
            if let (profileData, profileResponse) = try? await session.data(for: profileRequest),
               (profileResponse as? HTTPURLResponse)?.statusCode == 200 {
                accountEmail = ProviderUsageIdentity.claudeEmail(from: profileData)
            }
        }
        snapshot.accountEmail = accountEmail
        return snapshot
    }

    /// Converts provider response fields to percent used and absolute reset dates.
    static func decodeUsage(_ data: Data, provider: UsageProvider, now: Date = Date()) throws -> ProviderUsageSnapshot {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageFetchError.invalidResponse
        }
        var windows: [ProviderUsageWindow] = []
        var details: [ProviderUsageDetail] = []
        var plan: String?
        switch provider {
        case .codex:
            plan = ProviderUsageIdentity.planLabel(json["plan_type"] as? String)
            if let limits = json["rate_limit"] as? [String: Any] {
                for key in ["primary_window", "secondary_window"] {
                    guard let window = limits[key] as? [String: Any] else { continue }
                    let seconds = window["limit_window_seconds"] as? Double
                    let label: String
                    if seconds == 604800 { label = "Weekly limit" }
                    else if seconds == 18000 { label = "5-hour limit" }
                    else if let seconds, seconds > 0 { label = "\(Int(seconds / 3600))-hour limit" }
                    else { label = key == "primary_window" ? "Primary limit" : "Secondary limit" }
                    windows.append(ProviderUsageWindow(
                        label: label, usedPercent: validUsagePercent(window["used_percent"]),
                        resetsAt: (window["reset_at"] as? Double).map(Date.init(timeIntervalSince1970:))
                    ))
                }
            }
            if let credits = json["credits"] as? [String: Any] {
                if credits["unlimited"] as? Bool == true {
                    details.append(.init(label: "Credits", value: "Unlimited"))
                } else if let balance = credits["balance"] as? Double {
                    details.append(.init(label: "Credits", value: balance.formatted()))
                } else if let text = credits["balance"] as? String, let balance = Double(text), balance.isFinite {
                    details.append(.init(label: "Credits", value: balance.formatted()))
                }
            }
        case .claude:
            for (key, label) in [("five_hour", "Current session"), ("seven_day", "Weekly limit"),
                                 ("seven_day_sonnet", "Sonnet weekly"), ("seven_day_opus", "Opus weekly")] {
                guard let window = json[key] as? [String: Any] else { continue }
                windows.append(.init(label: label, usedPercent: validUsagePercent(window["utilization"]),
                                     resetsAt: parseUsageDate(window["resets_at"] as? String)))
            }
            // Extra usage is monthly spending, not a prepaid balance. The API reports cents.
            if let extra = json["extra_usage"] as? [String: Any], let enabled = extra["is_enabled"] as? Bool {
                details.append(.init(label: "Extra usage", value: enabled ? "Enabled" : "Disabled"))
                if enabled, let spent = extra["used_credits"] as? Double {
                    details.append(.init(label: "Monthly extra spend", value: (spent / 100).formatted(.currency(code: "USD"))))
                }
                if enabled, let limit = extra["monthly_limit"] as? Double {
                    details.append(.init(label: "Monthly extra limit", value: (limit / 100).formatted(.currency(code: "USD"))))
                }
            }
        case .grok:
            guard let config = json["config"] as? [String: Any] else { throw UsageFetchError.invalidResponse }
            plan = ProviderUsageIdentity.planLabel(config["subscriptionTier"] as? String ?? json["subscriptionTier"] as? String)
            let period = config["currentPeriod"] as? [String: Any]
            let end = parseUsageDate(period?["end"] as? String) ?? parseUsageDate(config["billingPeriodEnd"] as? String)
            let start = parseUsageDate(period?["end"] as? String) == nil ? parseUsageDate(config["billingPeriodStart"] as? String) : parseUsageDate(period?["start"] as? String)
            let label: String
            if let start, let end, (6...8).contains(end.timeIntervalSince(start) / 86400) { label = "Weekly limit" }
            else if let start, let end, (27...32).contains(end.timeIntervalSince(start) / 86400) { label = "Monthly limit" }
            else { label = "Subscription credits limit" }
            // The official CLI treats an omitted percentage as zero in unified credits responses.
            // Require the unified-billing marker; older or malformed payloads remain unknown.
            let percent = validUsagePercent(config["creditUsagePercent"])
                ?? (config["creditUsagePercent"] == nil && config["isUnifiedBillingUser"] as? Bool == true ? 0 : nil)
            windows.append(.init(label: label, usedPercent: percent, resetsAt: end))
            if let wallet = config["prepaidBalance"] as? [String: Any] {
                let cents = wallet.isEmpty ? 0 : (wallet["val"] as? Double ?? (wallet["val"] as? String).flatMap(Double.init))
                if let cents, cents.isFinite, cents >= 0 {
                    details.append(.init(label: "Credits", value: (cents / 100).formatted(.currency(code: "USD"))))
                }
            }
            guard windows[0].usedPercent != nil || end != nil || !details.isEmpty else { throw UsageFetchError.invalidResponse }
        }
        guard !windows.isEmpty || !details.isEmpty else { throw UsageFetchError.invalidResponse }
        return .init(provider: provider, plan: plan, windows: windows, details: details, updatedAt: now, source: .live)
    }

    private static func validUsagePercent(_ value: Any?) -> Double? {
        guard let value = value as? Double, value.isFinite, (0...100).contains(value) else { return nil }
        return value
    }

    private static func parseUsageDate(_ text: String?) -> Date? {
        guard let text else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    private func readCredentials(at path: String, provider: UsageProvider) throws -> [String: Any] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageFetchError.unavailable("Could not read \(provider.name) sign-in. Sign in with its CLI, then refresh.")
        }
        return json
    }


}

/// Errors never contain provider response bodies or credential values.
enum UsageFetchError: LocalizedError {
    case unavailable(String)
    case invalidResponse
    var errorDescription: String? {
        switch self {
        case .unavailable(let message): message
        case .invalidResponse: "The provider returned an unreadable usage response."
        }
    }
}
