import Foundation
import Observation

/// Keeps the last successful usage snapshot visible when refresh fails; manual snapshots never auto-refresh.
@MainActor
@Observable
final class ProviderUsageStore {
    private(set) var snapshots: [UsageProvider: ProviderUsageSnapshot] = [:]
    private(set) var errors: [UsageProvider: String] = [:]
    private(set) var refreshing: Set<UsageProvider> = []
    private let fetcher: any ProviderUsageFetching
    private let defaults: UserDefaults
    @ObservationIgnored private var autoRefreshTask: Task<Void, Never>?
    private let storageKey = "providerUsageSnapshots.v1"

    init(fetcher: any ProviderUsageFetching = ProviderUsageService(), defaults: UserDefaults = .standard) {
        self.fetcher = fetcher
        self.defaults = defaults

        if let data = defaults.data(forKey: storageKey),
            let saved = try? JSONDecoder().decode([ProviderUsageSnapshot].self, from: data)
        {
            for snapshot in saved { snapshots[snapshot.provider] = snapshot.normalizingUsageLabels() }
        }
    }

    /// Refreshes live providers in the background; manual snapshots remain explicitly user-owned.
    func startAutoRefresh(
        interval: Duration = .seconds(300),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        guard autoRefreshTask == nil else { return }
        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshAll()
                do { try await sleep(interval) } catch { return }
            }
        }
    }

    func stopAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }

    deinit { autoRefreshTask?.cancel() }

    func refreshAll() async {
        await withTaskGroup(of: Void.self) { group in
            for provider in UsageProvider.allCases where snapshots[provider]?.source != .manual {
                group.addTask { await self.refresh(provider) }
            }
        }
    }

    func refresh(_ provider: UsageProvider, useLive: Bool = false, allowKeychainPrompt: Bool = false) async {
        guard !refreshing.contains(provider), useLive || snapshots[provider]?.source != .manual else { return }
        refreshing.insert(provider)
        defer { refreshing.remove(provider) }
        do {
            let snapshot = try await fetcher.fetchUsage(for: provider, allowKeychainPrompt: allowKeychainPrompt)

            // A user may save a manual snapshot while an earlier refresh is still running.
            if !useLive, snapshots[provider]?.source == .manual { return }

            snapshots[provider] = snapshot.normalizingUsageLabels()
            errors[provider] = nil
            persistUsageSnapshots()
        } catch is CancellationError {
            return
        } catch {
            errors[provider] =
                (error as? UsageFetchError)?.localizedDescription
                ?? "Could not refresh usage. Check your connection and try again."
        }
    }

    func saveManualSnapshot(_ snapshot: ProviderUsageSnapshot) {
        var snapshot = snapshot

        snapshot.source = .manual
        snapshot.updatedAt = Date()
        snapshots[snapshot.provider] = snapshot.normalizingUsageLabels()
        errors[snapshot.provider] = nil
        persistUsageSnapshots()
    }

    private func persistUsageSnapshots() {
        if let data = try? JSONEncoder().encode(Array(snapshots.values)) {
            defaults.set(data, forKey: storageKey)
        }
    }
}
