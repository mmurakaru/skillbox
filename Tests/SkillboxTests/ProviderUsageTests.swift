import Foundation
import Testing

@testable import Skillbox

struct ProviderUsageTests {
    @Test func codexPreservesWeeklyOnlyQuotaAndCreditUnits() throws {
        let data = Data(
            #"{"plan_type":"pro","rate_limit":{"secondary_window":{"used_percent":1,"reset_at":1792328400,"limit_window_seconds":604800}},"credits":{"balance":"0"}}"#
                .utf8)
        let snapshot = try ProviderUsageService.decodeUsage(data, provider: .codex)

        #expect(snapshot.windows.count == 1)
        #expect(snapshot.windows[0].label == "Weekly limit")
        #expect(snapshot.windows[0].usedPercent == 1)
        #expect(snapshot.windows[0].resetsAt == Date(timeIntervalSince1970: 1_792_328_400))
        #expect(snapshot.details == [.init(label: "Credits", value: "0")])
    }

    @Test func claudeDistinguishesMeasuredZeroFromUnknown() throws {
        let data = Data(
            #"{"five_hour":{"utilization":0,"resets_at":"2026-10-11T14:50:00.123Z"},"seven_day":{"utilization":null,"resets_at":null},"seven_day_sonnet":{"utilization":12,"resets_at":"2026-10-16T16:00:00Z"},"extra_usage":{"is_enabled":true,"used_credits":150,"monthly_limit":1000}}"#
                .utf8)
        let snapshot = try ProviderUsageService.decodeUsage(data, provider: .claude)

        #expect(snapshot.windows.map(\.usedPercent) == [0, nil, 12])
        #expect(snapshot.windows[0].resetsAt != nil)
        #expect(snapshot.windows[1].resetsAt == nil)
        #expect(snapshot.windows[2].resetsAt != nil)
        #expect(snapshot.details.first?.label == "Extra usage")
        #expect(snapshot.details.contains { $0.label == "Monthly extra spend" })
        #expect(!snapshot.details.contains { $0.label == "Credits" })
    }

    @Test func invalidPercentIsUnknownAndUnknownSchemaFails() throws {
        let data = Data(#"{"five_hour":{"utilization":101}}"#.utf8)
        let snapshot = try ProviderUsageService.decodeUsage(data, provider: .claude)

        #expect(snapshot.windows[0].usedPercent == nil)
        #expect(throws: (any Error).self) {
            try ProviderUsageService.decodeUsage(Data(#"{"unexpected":true}"#.utf8), provider: .codex)
        }
    }

    @MainActor
    @Test func failedRefreshRetainsPersistedSnapshotAndManualEntrySurvivesReload() async throws {
        let suite = "ProviderUsageTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))

        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ProviderUsageStore(fetcher: UnavailableUsageFetcher(), defaults: defaults)
        let snapshot = ProviderUsageSnapshot(
            provider: .grok, plan: "SuperGrok",
            windows: [
                .init(label: "Weekly limit", usedPercent: 0, resetsAt: nil)
            ], details: [.init(label: "Credits", value: "0 USD")], updatedAt: Date(), source: .manual)

        store.saveManualSnapshot(snapshot)
        let saved = store.snapshots[.grok]

        await store.refreshAll()
        #expect(store.snapshots[.grok] == saved)
        #expect(store.errors[.grok] == nil)
        await store.refresh(.grok, useLive: true)
        #expect(store.snapshots[.grok] == saved)
        #expect(store.errors[.grok] != nil)
        #expect(store.refreshing.isEmpty)
        let restored = ProviderUsageStore(fetcher: UnavailableUsageFetcher(), defaults: defaults)

        #expect(restored.snapshots[.grok] == saved)
    }
}

private struct UnavailableUsageFetcher: ProviderUsageFetching {
    func fetchUsage(for provider: UsageProvider, allowKeychainPrompt: Bool) async throws -> ProviderUsageSnapshot {
        throw UsageFetchError.unavailable("Usage temporarily unavailable.")
    }
}

struct ProviderUsageRefreshTests {
    @MainActor @Test func savedGrokBrandLabelsMigrateWithoutLosingQuotaOrPlan() throws {
        let suite = "ProviderUsageMigration.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))

        defer { defaults.removePersistentDomain(forName: suite) }
        let reset = Date(timeIntervalSince1970: 1000)
        let old = ProviderUsageSnapshot(
            provider: .grok, plan: "SuperGrok Heavy",
            windows: [
                .init(label: "Weekly SuperGrok limit", usedPercent: 42, resetsAt: reset)
            ], updatedAt: reset, source: .manual)

        defaults.set(try JSONEncoder().encode([old]), forKey: "providerUsageSnapshots.v1")
        let store = ProviderUsageStore(fetcher: UnavailableUsageFetcher(), defaults: defaults)

        #expect(store.snapshots[.grok]?.windows.first?.label == "Weekly limit")
        #expect(store.snapshots[.grok]?.windows.first?.usedPercent == 42)
        #expect(store.snapshots[.grok]?.windows.first?.resetsAt == reset)
        #expect(store.snapshots[.grok]?.plan == "SuperGrok Heavy")
    }

    @MainActor @Test func intervalRefreshRepeatsWithoutPromptingOrOverwritingManualSnapshots() async throws {
        let suite = "ProviderUsageInterval.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))

        defer { defaults.removePersistentDomain(forName: suite) }
        let fetcher = IntervalUsageFetcher()
        let clock = UsageRefreshTestClock()
        let store = ProviderUsageStore(fetcher: fetcher, defaults: defaults)

        store.saveManualSnapshot(
            .init(
                provider: .grok, plan: "SuperGrok", windows: [.init(label: "Weekly limit", usedPercent: 20, resetsAt: nil)],
                updatedAt: Date(), source: .manual))
        store.startAutoRefresh(sleep: { try await clock.sleep($0) })
        await clock.waitUntilSleeping()
        let initialProviders = await fetcher.providers

        #expect(Set(initialProviders) == Set([UsageProvider.codex, .claude]))
        #expect(await clock.interval == .seconds(300))
        await clock.advance()
        await clock.waitUntilSleeping()
        #expect(await fetcher.providers.count == 4)
        #expect(store.snapshots[.grok]?.windows.first?.usedPercent == 20)
        store.stopAutoRefresh()
        await clock.advance()
        for _ in 0..<20 { await Task.yield() }
        #expect(await fetcher.providers.count == 4)
    }
}

private actor IntervalUsageFetcher: ProviderUsageFetching {
    private(set) var providers: [UsageProvider] = []
    func fetchUsage(for provider: UsageProvider, allowKeychainPrompt: Bool) async throws -> ProviderUsageSnapshot {
        #expect(!allowKeychainPrompt)
        providers.append(provider)

        return .init(
            provider: provider, windows: [.init(label: "Weekly limit", usedPercent: 10, resetsAt: nil)], updatedAt: Date(), source: .live)
    }
}

private actor UsageRefreshTestClock {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var interval: Duration?
    private var waitingTests: [CheckedContinuation<Void, Never>] = []
    func sleep(_ duration: Duration) async throws {
        interval = duration
        await withCheckedContinuation {
            continuation = $0
            for waitingTest in waitingTests { waitingTest.resume() }
            waitingTests.removeAll()
        }
        try Task.checkCancellation()
    }
    func waitUntilSleeping() async {
        if continuation != nil { return }

        await withCheckedContinuation { waitingTests.append($0) }
    }
    func advance() {
        let waiting = continuation

        continuation = nil
        waiting?.resume()
    }
}
