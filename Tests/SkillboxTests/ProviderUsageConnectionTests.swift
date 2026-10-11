import Foundation
import Security
import AppKit
import Testing
@testable import Skillbox

@Suite(.serialized)
struct ProviderUsageConnectionTests {
    @Test func backgroundKeychainQueryForbidsPermissionDialogs() {
        let query = ClaudeUsageCredentials.keychainQuery(allowPrompt: false)
        #expect(query[kSecUseAuthenticationUI as String] as? String == kSecUseAuthenticationUIFail as String)
        #expect(query[kSecAttrService as String] as? String == "Claude Code-credentials")
        let explicit = ClaudeUsageCredentials.keychainQuery(allowPrompt: true)
        #expect(explicit[kSecUseAuthenticationUI as String] as? String == kSecUseAuthenticationUIAllow as String)
        // TypeSafe has a separate credential entry; the usage reader never queries it.
        #expect(query[kSecAttrService as String] as? String != "ai.skillbox.typesafe")
    }

    @Test func automaticClaudeCredentialsNeverCallForeignKeychainReader() throws {
        var calls = 0
        #expect(throws: (any Error).self) {
            try ClaudeUsageCredentials.loadCredentials(configuredHome: nil, defaultHome: "/nonexistent-fixture-home", allowPrompt: false) { _ in
                calls += 1
                return [:]
            }
        }
        #expect(calls == 0)
        _ = try ClaudeUsageCredentials.loadCredentials(configuredHome: nil, defaultHome: "/nonexistent-fixture-home", allowPrompt: true) { allowPrompt in
            #expect(allowPrompt)
            calls += 1
            return ["fixture": true]
        }
        #expect(calls == 1)
    }

    @Test func customClaudeProfileDoesNotFallBackToAnotherAccountsKeychain() {
        var calls = 0
        #expect(throws: (any Error).self) {
            try ClaudeUsageCredentials.loadCredentials(configuredHome: "/nonexistent-custom-profile", allowPrompt: true) { _ in
                calls += 1
                return [:]
            }
        }
        #expect(calls == 0)
    }

    @Test func bundledProviderLogosAreValidVectorImages() throws {
        for provider in UsageProvider.allCases {
            let url = try #require(Bundle.module.url(forResource: provider.rawValue, withExtension: "pdf", subdirectory: "ProviderLogos"))
            let image = try #require(NSImage(contentsOf: url))
            #expect(image.size.width > 0)
            #expect(image.size.height > 0)
        }
    }

    @Test func signedAppResourceLayoutLoadsLogosWithoutBuildDirectory() throws {
        let resources = FileManager.default.temporaryDirectory.appendingPathComponent("UsageLogoResources-\(UUID().uuidString)")
        let directory = resources.appendingPathComponent("Skillbox_Skillbox.bundle/ProviderLogos")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: resources) }
        for provider in UsageProvider.allCases {
            let source = try #require(Bundle.module.url(forResource: provider.rawValue, withExtension: "pdf", subdirectory: "ProviderLogos"))
            let target = directory.appendingPathComponent("\(provider.rawValue).pdf")
            try FileManager.default.copyItem(at: source, to: target)
            #expect(ProviderUsageLogo.logoURL(for: provider, appResourceURL: resources) == target)
        }
    }

    @MainActor
    @Test func automaticRefreshNeverOptsIntoKeychainDialogs() async throws {
        let suite = "UsageConnectionTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let fetcher = UsagePermissionRecorder()
        let store = ProviderUsageStore(fetcher: fetcher, defaults: defaults)
        await store.refreshAll()
        let automatic = await fetcher.requests
        #expect(automatic.count == 3)
        #expect(automatic.allSatisfy { !$0.allowPrompt })
        await store.refresh(.claude, useLive: true, allowKeychainPrompt: true)
        let explicit = await fetcher.requests
        #expect(explicit.last?.provider == .claude)
        #expect(explicit.last?.allowPrompt == true)
        await store.refreshAll()
        let afterConnection = await fetcher.requests
        #expect(afterConnection.suffix(3).allSatisfy { !$0.allowPrompt })
    }

    @Test(arguments: ["personal@example.com", "work@example.com"])
    func claudeShowsEmailForTheAccountWhoseUsageWasFetched(email: String) async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [UsageFixtureURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel(); UsageFixtureURLProtocol.handler = nil }
        UsageFixtureURLProtocol.handler = { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-access-token")
            let data: Data
            if request.url?.path == "/api/oauth/usage" {
                data = Data(#"{"five_hour":{"utilization":0},"seven_day":{"utilization":25}}"#.utf8)
            } else {
                #expect(request.url?.path == "/api/oauth/profile")
                data = try JSONSerialization.data(withJSONObject: ["account": ["email": email]])
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }
        let service = ProviderUsageService(session: session, claudeCLIReader: nil, claudeCredentialsReader: { allowPrompt in
            #expect(!allowPrompt)
            return .init(values: ["claudeAiOauth": ["accessToken": "fixture-access-token", "subscriptionType": "pro"]], source: .keychain)
        })
        let snapshot = try await service.fetchUsage(for: .claude)
        #expect(snapshot.accountEmail == email)
        #expect(snapshot.plan == "Pro")
        #expect(snapshot.windows.map(\.usedPercent) == [0, 25])
        #expect(!snapshot.details.contains { $0.label == "Renews" || $0.label == "Subscription price" })
    }

    @Test func connectedClaudeUsesMemoryForBackgroundRefresh() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [UsageFixtureURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel(); UsageFixtureURLProtocol.handler = nil }
        UsageFixtureURLProtocol.handler = { request in
            let data = request.url?.path == "/api/oauth/profile"
                ? Data(#"{"account":{"email":"connected@example.com"}}"#.utf8)
                : Data(#"{"seven_day":{"utilization":3}}"#.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }
        let service = ProviderUsageService(session: session, claudeCLIReader: nil, claudeCredentialsReader: { allowPrompt in
            if !allowPrompt { throw UsageFetchError.claudeKeychainPermissionRequired }
            return .init(values: ["claudeAiOauth": ["accessToken": "fixture-access-token", "subscriptionType": "pro"]], source: .keychain)
        })
        _ = try await service.fetchUsage(for: .claude, allowKeychainPrompt: true)
        let automatic = try await service.fetchUsage(for: .claude)
        #expect(automatic.accountEmail == "connected@example.com")
    }

    @Test func claudeFileFallbackRechecksActiveAccount() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ClaudeAccountFixture-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent(".credentials.json")
        func writeCredentials(_ token: String) throws {
            try JSONSerialization.data(withJSONObject: ["claudeAiOauth": ["accessToken": token, "subscriptionType": "pro"]]).write(to: path)
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [UsageFixtureURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel(); UsageFixtureURLProtocol.handler = nil }
        UsageFixtureURLProtocol.handler = { request in
            let email = request.value(forHTTPHeaderField: "Authorization") == "Bearer personal-fixture" ? "personal@example.com" : "work@example.com"
            let data = request.url?.path == "/api/oauth/profile"
                ? try JSONSerialization.data(withJSONObject: ["account": ["email": email]])
                : Data(#"{"seven_day":{"utilization":3}}"#.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }
        let service = ProviderUsageService(session: session, claudeCLIReader: nil, claudeCredentialsReader: { allowPrompt in
            try ClaudeUsageCredentials.readCredentials(defaultHome: directory.path, allowPrompt: allowPrompt)
        })
        try writeCredentials("personal-fixture")
        #expect(try await service.fetchUsage(for: .claude).accountEmail == "personal@example.com")
        try writeCredentials("work-fixture")
        #expect(try await service.fetchUsage(for: .claude).accountEmail == "work@example.com")
        try FileManager.default.removeItem(at: path)
        await #expect(throws: (any Error).self) { try await service.fetchUsage(for: .claude) }
        try Data("invalid".utf8).write(to: path)
        await #expect(throws: (any Error).self) { try await service.fetchUsage(for: .claude) }
    }

    @Test func failedProfileDoesNotHideQuotaOrInventAccountIdentity() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [UsageFixtureURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel(); UsageFixtureURLProtocol.handler = nil }
        UsageFixtureURLProtocol.handler = { request in
            let status = request.url?.path == "/api/oauth/profile" ? 503 : 200
            return (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!,
                    Data(#"{"seven_day":{"utilization":3}}"#.utf8))
        }
        let service = ProviderUsageService(session: session, claudeCLIReader: nil, claudeCredentialsReader: { _ in
             .init(values: ["claudeAiOauth": ["accessToken": "fixture-access-token", "subscriptionType": "max"]], source: .file)
        })
        let snapshot = try await service.fetchUsage(for: .claude)
        #expect(snapshot.accountEmail == nil)
        #expect(snapshot.plan == "Max")
        #expect(snapshot.windows.first?.usedPercent == 3)
    }

    @Test func codexIdentityAndPlanLabelsDoNotRequireKeychain() throws {
        let data = try JSONSerialization.data(withJSONObject: ["email": "codex@example.com"])
        let token = "header.\(data.base64EncodedString().replacingOccurrences(of: "=", with: "")).signature"
        #expect(ProviderUsageIdentity.codexEmail(from: token) == "codex@example.com")
        #expect(ProviderUsageIdentity.codexEmail(from: "invalid") == nil)
        #expect(ProviderUsageIdentity.planLabel("prolite") == "Pro Lite")
        #expect(ProviderUsageIdentity.planLabel("super_grok_heavy") == "SuperGrok Heavy")
    }

    @Test func grokRequiresUnexpiredConsumerSignInAndPreservesAccount() throws {
        let now = Date(timeIntervalSince1970: 1000)
        let valid = Data(#"{"https://auth.x.ai::fixture":{"key":"fixture-token","email":"grok@example.com","expires_at":2000},"https://accounts.x.ai/sign-in":{"key":"legacy-token","expires_at":2000}}"#.utf8)
        let credentials = try GrokUsageCredentials.decodeCredentials(valid, now: now)
        #expect(credentials.email == "grok@example.com")
        #expect(credentials.accessToken == "fixture-token")
        let expired = Data(#"{"https://auth.x.ai::fixture":{"key":"fixture-token","expires_at":999}}"#.utf8)
        #expect(throws: (any Error).self) { try GrokUsageCredentials.decodeCredentials(expired, now: now) }
        let apiKey = Data(#"{"https://auth.x.ai::fixture":{"key":"xai-management-key","expires_at":2000}}"#.utf8)
        #expect(throws: (any Error).self) { try GrokUsageCredentials.decodeCredentials(apiKey, now: now) }
    }

    @Test func grokUnknownUsageIsNotZeroAndCreditsKeepDollarUnits() throws {
        let data = Data(#"{"config":{"subscriptionTier":"super_grok","currentPeriod":{"start":"2026-10-11T00:00:00Z","end":"2026-10-18T00:00:00Z"},"prepaidBalance":{"val":"1446"}}}"#.utf8)
        let snapshot = try ProviderUsageService.decodeUsage(data, provider: .grok)
        #expect(snapshot.plan == "SuperGrok")
        #expect(snapshot.windows.first?.label == "Weekly limit")
        #expect(snapshot.windows.first?.usedPercent == nil)
        #expect(snapshot.details.first?.value == 14.46.formatted(.currency(code: "USD")))
        let zero = try ProviderUsageService.decodeUsage(Data(#"{"config":{"creditUsagePercent":0,"prepaidBalance":{}}}"#.utf8), provider: .grok)
        #expect(zero.windows.first?.usedPercent == 0)
        #expect(zero.details.first?.value == 0.0.formatted(.currency(code: "USD")))
        #expect(throws: (any Error).self) { try ProviderUsageService.decodeUsage(Data(#"{"config":{}}"#.utf8), provider: .grok) }
    }

    @Test func grokUnifiedBillingOmitsZeroPercentage() throws {
        let data = Data(#"{"config":{"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","start":"2026-10-11T00:00:00Z","end":"2026-10-18T00:00:00Z"},"isUnifiedBillingUser":true,"prepaidBalance":{"val":0}}}"#.utf8)
        let snapshot = try ProviderUsageService.decodeUsage(data, provider: .grok)
        #expect(snapshot.windows.first?.usedPercent == 0)
        #expect(snapshot.windows.first?.label == "Weekly limit")
        let invalid = Data(#"{"config":{"creditUsagePercent":"invalid","isUnifiedBillingUser":true,"prepaidBalance":{"val":0}}}"#.utf8)
        #expect(try ProviderUsageService.decodeUsage(invalid, provider: .grok).windows.first?.usedPercent == nil)
    }

    @Test func grokPlanComesFromSettingsUsingTheSameAccount() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [UsageFixtureURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel(); UsageFixtureURLProtocol.handler = nil }
        UsageFixtureURLProtocol.handler = { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-access-token")
            #expect(request.value(forHTTPHeaderField: "x-xai-token-auth") == "xai-grok-cli")
            #expect(request.value(forHTTPHeaderField: "x-userid") == "fixture-user")
            let data = request.url?.path == "/v1/settings"
                ? Data(#"{"subscription_tier_display":"SuperGrok"}"#.utf8)
                : Data(#"{"config":{"creditUsagePercent":8,"prepaidBalance":{"val":0}}}"#.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }
        let service = ProviderUsageService(session: session, grokCredentialsReader: {
            GrokUsageCredentials(accessToken: "fixture-access-token", email: "personal@example.com", userID: "fixture-user")
        })
        let snapshot = try await service.fetchUsage(for: .grok)
        #expect(snapshot.plan == "SuperGrok")
        #expect(snapshot.accountEmail == "personal@example.com")
        #expect(snapshot.windows.first?.usedPercent == 8)
    }

    @Test func failedGrokSettingsDoesNotHideUsage() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [UsageFixtureURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel(); UsageFixtureURLProtocol.handler = nil }
        UsageFixtureURLProtocol.handler = { request in
            let status = request.url?.path == "/v1/settings" ? 503 : 200
            return (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!,
                    Data(#"{"config":{"creditUsagePercent":8}}"#.utf8))
        }
        let service = ProviderUsageService(session: session, grokCredentialsReader: {
            GrokUsageCredentials(accessToken: "fixture-access-token", email: nil, userID: nil)
        })
        let snapshot = try await service.fetchUsage(for: .grok)
        #expect(snapshot.plan == nil)
        #expect(snapshot.windows.first?.usedPercent == 8)
    }
}

private actor UsagePermissionRecorder: ProviderUsageFetching {
    struct Request: Sendable { let provider: UsageProvider; let allowPrompt: Bool }
    private(set) var requests: [Request] = []
    func fetchUsage(for provider: UsageProvider, allowKeychainPrompt: Bool) async throws -> ProviderUsageSnapshot {
        requests.append(.init(provider: provider, allowPrompt: allowKeychainPrompt))
        throw UsageFetchError.unavailable("Fixture has no connection")
    }
}

private final class UsageFixtureURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (response, data) = try Self.handler!(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
