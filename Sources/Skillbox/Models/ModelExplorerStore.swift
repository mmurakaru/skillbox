import Foundation
import Observation
import ModelInventory

/// Hugging Face Hub search behind the Explore tab. Caches the last results so the tab still shows them offline.
@MainActor
@Observable
final class ModelExplorerStore {
    private(set) var results: [HuggingFaceHubModel] = []
    private(set) var lastSynced: Date?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var hasSearchedThisSession = false

    var query = HuggingFaceHubQuery()
    var sizeBucket: ModelParameterSizeBucket = .any

    private let client: any HuggingFaceHubSearching
    private let cacheURL: URL
    // Bumped per search so a slow, older response cannot replace newer results.
    private var searchGeneration = 0

    init(client: any HuggingFaceHubSearching = HuggingFaceHubClient(), cacheURL: URL = ModelExplorerStore.defaultCacheURL()) {
        self.client = client
        self.cacheURL = cacheURL
        loadCache()
    }

    /// Server results narrowed by the parameter size filter.
    var displayedResults: [HuggingFaceHubModel] {
        results.filter { sizeBucket.matches($0.parameterHint) }
    }

    func search() async {
        searchGeneration += 1
        let generation = searchGeneration
        hasSearchedThisSession = true
        isLoading = true
        errorMessage = nil
        do {
            let found = try await client.search(query)
            guard generation == searchGeneration else { return }
            results = found
            lastSynced = Date()
            saveCache()
        } catch {
            guard generation == searchGeneration else { return }
            errorMessage = "Could not reach Hugging Face. Showing the last synced results."
        }
        isLoading = false
    }

    /// Runs the first live search of this app session; later visits keep the current results.
    func searchOncePerSession() async {
        guard !hasSearchedThisSession else { return }
        await search()
    }

    private struct CachePayload: Codable {
        var models: [HuggingFaceHubModel]
        var lastSynced: Date
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: cacheURL),
              let payload = try? JSONDecoder().decode(CachePayload.self, from: data) else { return }
        results = payload.models
        lastSynced = payload.lastSynced
    }

    private func saveCache() {
        let payload = CachePayload(models: results, lastSynced: lastSynced ?? Date())
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: cacheURL, options: .atomic)
    }

    nonisolated static func defaultCacheURL() -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return caches.appending(path: "Skillbox/model-explorer-cache.json")
    }
}
