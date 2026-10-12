import Foundation
import Security

// swiftlint:disable no_untyped_dictionaries no_any_parameters - JSON trust boundary: parses provider usage payloads whose fields vary by plan.

/// Fetches subscription usage without refreshing or writing provider-owned credentials.
protocol ProviderUsageFetching: Sendable {
    func fetchUsage(for provider: UsageProvider, allowKeychainPrompt: Bool) async throws -> ProviderUsageSnapshot
}

/// Reads existing CLI sign-ins and sends credentials only to the matching provider endpoint.
actor ProviderUsageService: ProviderUsageFetching {
    private var cachedClaudeCredentials: ClaudeUsageCredentials.ReadResult?
    private let session: URLSession
    private let claudeCLIReader: (@Sendable () async throws -> ProviderUsageSnapshot?)?
    private let claudeCredentialsReader: @Sendable (Bool) throws -> ClaudeUsageCredentials.ReadResult
    private let grokCredentialsReader: @Sendable () throws -> GrokUsageCredentials
    init(
        session: URLSession? = nil,
        claudeCLIReader: (@Sendable () async throws -> ProviderUsageSnapshot?)? = {
            try await ClaudeCLIUsageReader.fetchInstalledCLIUsage()
        },
        claudeCredentialsReader: @escaping @Sendable (Bool) throws -> ClaudeUsageCredentials.ReadResult = {
            try ClaudeUsageCredentials.readCredentials(allowPrompt: $0)
        },
        grokCredentialsReader: @escaping @Sendable () throws -> GrokUsageCredentials = { try GrokUsageCredentials.load() }
    ) {
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

        var prepared = try prepareUsageRequest(for: provider, allowKeychainPrompt: allowKeychainPrompt)

        prepared.request.cachePolicy = .reloadIgnoringLocalCacheData
        prepared.request.timeoutInterval = 20
        prepared.request.setValue("Bearer \(prepared.token)", forHTTPHeaderField: "Authorization")
        prepared.request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: prepared.request)

        try checkUsageResponse(response, provider: provider)
        var snapshot = try Self.decodeUsage(data, provider: provider)
        var accountEmail = prepared.accountEmail

        if provider == .grok {
            snapshot.plan = await grokPlan(reusing: prepared.request) ?? snapshot.plan
        }

        if provider == .claude, let oauth = prepared.credentials["claudeAiOauth"] as? [String: Any] {
            cachedClaudeCredentials = prepared.claudeRead?.source == .keychain ? prepared.claudeRead : nil
            snapshot.plan = ProviderUsageIdentity.planLabel(oauth["subscriptionType"] as? String)
            accountEmail = await claudeAccountEmail(token: prepared.token)
        }

        snapshot.accountEmail = accountEmail

        return snapshot
    }

    /// One provider's usage request plus the credentials it was built from.
    private struct PreparedUsageRequest {
        var request: URLRequest
        let token: String
        let accountEmail: String?
        let credentials: [String: Any]
        let claudeRead: ClaudeUsageCredentials.ReadResult?
    }

    private func prepareUsageRequest(for provider: UsageProvider, allowKeychainPrompt: Bool) throws -> PreparedUsageRequest {
        switch provider {
        case .grok: try grokUsageRequest()
        case .codex: try codexUsageRequest()
        case .claude: try claudeUsageRequest(allowKeychainPrompt: allowKeychainPrompt)
        }
    }

    private func grokUsageRequest() throws -> PreparedUsageRequest {
        let grok = try grokCredentialsReader()
        var request = URLRequest(url: try Self.endpoint("https://cli-chat-proxy.grok.com/v1/billing?format=credits"))

        request.setValue("xai-grok-cli", forHTTPHeaderField: "x-xai-token-auth")

        if let userID = grok.userID { request.setValue(userID, forHTTPHeaderField: "x-userid") }

        return PreparedUsageRequest(request: request, token: grok.accessToken, accountEmail: grok.email, credentials: [:], claudeRead: nil)
    }

    private func codexUsageRequest() throws -> PreparedUsageRequest {
        let home = ProcessInfo.processInfo.environment["CODEX_HOME"] ?? "\(NSHomeDirectory())/.codex"
        let credentials = try readCredentials(at: "\(home)/auth.json", provider: .codex)

        guard let tokens = credentials["tokens"] as? [String: Any],
            let accessToken = tokens["access_token"] as? String, !accessToken.isEmpty
        else {
            throw UsageFetchError.unavailable("Sign in with Codex to read subscription usage. API keys do not report plan limits.")
        }

        var request = URLRequest(url: try Self.endpoint("https://chatgpt.com/backend-api/wham/usage"))

        if let accountID = tokens["account_id"] as? String, !accountID.isEmpty {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        request.setValue("codex-cli", forHTTPHeaderField: "User-Agent")

        return PreparedUsageRequest(
            request: request, token: accessToken,
            accountEmail: ProviderUsageIdentity.codexEmail(from: tokens["id_token"] as? String),
            credentials: credentials, claudeRead: nil
        )
    }

    private func claudeUsageRequest(allowKeychainPrompt: Bool) throws -> PreparedUsageRequest {
        let read: ClaudeUsageCredentials.ReadResult

        if !allowKeychainPrompt, let cachedClaudeCredentials {
            do { read = try claudeCredentialsReader(false) } catch UsageFetchError.claudeKeychainPermissionRequired {
                read = cachedClaudeCredentials
            }
        } else {
            read = try claudeCredentialsReader(allowKeychainPrompt)
        }

        if read.source == .file { cachedClaudeCredentials = nil }

        guard let oauth = read.values["claudeAiOauth"] as? [String: Any],
            let accessToken = oauth["accessToken"] as? String, !accessToken.isEmpty
        else {
            throw UsageFetchError.unavailable("Sign in with Claude Code, then refresh usage.")
        }

        var request = URLRequest(url: try Self.endpoint("https://api.anthropic.com/api/oauth/usage"))

        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

        return PreparedUsageRequest(request: request, token: accessToken, accountEmail: nil, credentials: read.values, claudeRead: read)
    }

    private func checkUsageResponse(_ response: URLResponse, provider: UsageProvider) throws {
        guard let response = response as? HTTPURLResponse else { throw UsageFetchError.invalidResponse }

        switch response.statusCode {
        case 200: return
        case 401, 403:
            if provider == .claude { cachedClaudeCredentials = nil }

            throw UsageFetchError.unavailable("Usage access was rejected. Sign in with \(provider.name) again, then refresh.")
        case 429:
            throw UsageFetchError.unavailable("Too many usage requests. Try refreshing later.")
        default:
            throw UsageFetchError.unavailable("\(provider.name) usage is unavailable (HTTP \(response.statusCode)).")
        }
    }

    /// Grok's CLI enriches billing with the plan from /settings, sent with the same captured account headers.
    private func grokPlan(reusing billingRequest: URLRequest) async -> String? {
        var settingsRequest = billingRequest

        settingsRequest.url = try? Self.endpoint("https://cli-chat-proxy.grok.com/v1/settings")
        settingsRequest.timeoutInterval = 5
        guard let (settingsData, settingsResponse) = try? await session.data(for: settingsRequest),
            (settingsResponse as? HTTPURLResponse)?.statusCode == 200,
            let settings = try? JSONSerialization.jsonObject(with: settingsData) as? [String: Any]
        else { return nil }

        return ProviderUsageIdentity.planLabel(
            settings["subscription_tier_display"] as? String ?? settings["subscription_tier"] as? String)
    }

    /// Profile and usage use the same captured token even if the CLI switches accounts mid-request.
    private func claudeAccountEmail(token: String) async -> String? {
        guard let url = try? Self.endpoint("https://api.anthropic.com/api/oauth/profile") else { return nil }

        var profileRequest = URLRequest(url: url)

        profileRequest.timeoutInterval = 5
        profileRequest.cachePolicy = .reloadIgnoringLocalCacheData
        profileRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        profileRequest.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        guard let (profileData, profileResponse) = try? await session.data(for: profileRequest),
            (profileResponse as? HTTPURLResponse)?.statusCode == 200
        else { return nil }

        return ProviderUsageIdentity.claudeEmail(from: profileData)
    }

    private static func endpoint(_ string: String) throws -> URL {
        guard let url = URL(string: string) else { throw UsageFetchError.invalidResponse }

        return url
    }

    /// Converts provider response fields to percent used and absolute reset dates.
    static func decodeUsage(_ data: Data, provider: UsageProvider, now: Date = Date()) throws -> ProviderUsageSnapshot {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageFetchError.invalidResponse
        }

        let decoded: DecodedUsage

        switch provider {
        case .codex: decoded = decodeCodexUsage(json)
        case .claude: decoded = decodeClaudeUsage(json)
        case .grok: decoded = try decodeGrokUsage(json)
        }

        guard !decoded.windows.isEmpty || !decoded.details.isEmpty else { throw UsageFetchError.invalidResponse }

        return .init(
            provider: provider, plan: decoded.plan, windows: decoded.windows, details: decoded.details, updatedAt: now, source: .live)
    }

    private struct DecodedUsage {
        var plan: String?
        var windows: [ProviderUsageWindow] = []
        var details: [ProviderUsageDetail] = []
    }

    private static func decodeCodexUsage(_ json: [String: Any]) -> DecodedUsage {
        var decoded = DecodedUsage(plan: ProviderUsageIdentity.planLabel(json["plan_type"] as? String))

        if let limits = json["rate_limit"] as? [String: Any] {
            for key in ["primary_window", "secondary_window"] {
                guard let window = limits[key] as? [String: Any] else { continue }

                decoded.windows.append(
                    ProviderUsageWindow(
                        label: codexWindowLabel(seconds: window["limit_window_seconds"] as? Double, key: key),
                        usedPercent: validUsagePercent(window["used_percent"]),
                        resetsAt: (window["reset_at"] as? Double).map(Date.init(timeIntervalSince1970:))
                    ))
            }
        }

        if let credits = json["credits"] as? [String: Any] {
            if credits["unlimited"] as? Bool == true {
                decoded.details.append(.init(label: "Credits", value: "Unlimited"))
            } else if let balance = credits["balance"] as? Double {
                decoded.details.append(.init(label: "Credits", value: balance.formatted()))
            } else if let text = credits["balance"] as? String, let balance = Double(text), balance.isFinite {
                decoded.details.append(.init(label: "Credits", value: balance.formatted()))
            }
        }

        return decoded
    }

    private static func codexWindowLabel(seconds: Double?, key: String) -> String {
        if seconds == 604800 { return "Weekly limit" }

        if seconds == 18000 { return "5-hour limit" }

        if let seconds, seconds > 0 { return "\(Int(seconds / 3600))-hour limit" }

        return key == "primary_window" ? "Primary limit" : "Secondary limit"
    }

    private static func decodeClaudeUsage(_ json: [String: Any]) -> DecodedUsage {
        var decoded = DecodedUsage()

        for (key, label) in [
            ("five_hour", "Current session"), ("seven_day", "Weekly limit"),
            ("seven_day_sonnet", "Sonnet weekly"), ("seven_day_opus", "Opus weekly"),
        ] {
            guard let window = json[key] as? [String: Any] else { continue }

            decoded.windows.append(
                .init(
                    label: label, usedPercent: validUsagePercent(window["utilization"]),
                    resetsAt: parseUsageDate(window["resets_at"] as? String)))
        }

        // Extra usage is monthly spending, not a prepaid balance. The API reports cents.
        if let extra = json["extra_usage"] as? [String: Any], let enabled = extra["is_enabled"] as? Bool {
            decoded.details.append(.init(label: "Extra usage", value: enabled ? "Enabled" : "Disabled"))

            if enabled, let spent = extra["used_credits"] as? Double {
                decoded.details.append(.init(label: "Monthly extra spend", value: (spent / 100).formatted(.currency(code: "USD"))))
            }

            if enabled, let limit = extra["monthly_limit"] as? Double {
                decoded.details.append(.init(label: "Monthly extra limit", value: (limit / 100).formatted(.currency(code: "USD"))))
            }
        }

        return decoded
    }

    private static func decodeGrokUsage(_ json: [String: Any]) throws -> DecodedUsage {
        guard let config = json["config"] as? [String: Any] else { throw UsageFetchError.invalidResponse }

        var decoded = DecodedUsage(
            plan: ProviderUsageIdentity.planLabel(config["subscriptionTier"] as? String ?? json["subscriptionTier"] as? String))
        let period = config["currentPeriod"] as? [String: Any]
        let end = parseUsageDate(period?["end"] as? String) ?? parseUsageDate(config["billingPeriodEnd"] as? String)
        let start =
            parseUsageDate(period?["end"] as? String) == nil
            ? parseUsageDate(config["billingPeriodStart"] as? String) : parseUsageDate(period?["start"] as? String)
        // Grok omits zero usage in unified billing; other missing percentages remain unknown.
        let percent =
            validUsagePercent(config["creditUsagePercent"])
            ?? (config["creditUsagePercent"] == nil && config["isUnifiedBillingUser"] as? Bool == true ? 0 : nil)

        decoded.windows.append(.init(label: grokWindowLabel(start: start, end: end), usedPercent: percent, resetsAt: end))

        if let wallet = config["prepaidBalance"] as? [String: Any] {
            let cents = wallet.isEmpty ? 0 : (wallet["val"] as? Double ?? (wallet["val"] as? String).flatMap(Double.init))

            if let cents, cents.isFinite, cents >= 0 {
                decoded.details.append(.init(label: "Credits", value: (cents / 100).formatted(.currency(code: "USD"))))
            }
        }

        guard percent != nil || end != nil || !decoded.details.isEmpty else { throw UsageFetchError.invalidResponse }

        return decoded
    }

    private static func grokWindowLabel(start: Date?, end: Date?) -> String {
        guard let start, let end else { return "Subscription credits limit" }

        let days = end.timeIntervalSince(start) / 86400

        if (6...8).contains(days) { return "Weekly limit" }

        if (27...32).contains(days) { return "Monthly limit" }

        return "Subscription credits limit"
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
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw UsageFetchError.unavailable("Could not read \(provider.name) sign-in. Sign in with its CLI, then refresh.")
        }

        return json
    }

}

/// Errors never contain provider response bodies or credential values.
enum UsageFetchError: LocalizedError {
    case unavailable(String)
    case invalidResponse
    case claudeKeychainPermissionRequired
    var errorDescription: String? {
        switch self {
        case .unavailable(let message): message
        case .invalidResponse: "The provider returned an unreadable usage response."
        case .claudeKeychainPermissionRequired:
            "Click Connect Claude Code to use your current sign-in. Automatic refresh does not access Claude Code's Keychain entry."
        }
    }
}
