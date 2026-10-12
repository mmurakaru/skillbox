import Foundation
import Observation
import ModelInventory

/// Hugging Face Hub search behind the Explore tab. Caches the last results so the tab still shows them offline.
@MainActor
@Observable
final class ModelExplorerStore {
    private(set) var results: [HuggingFaceHubModel] = []
    /// The search that produced `results`, so cached results never show under other filters.
    private(set) var resultsQuery = HuggingFaceHubQuery()
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
    /// The last successful search, kept apart from `results` so an offline retry of that query can restore it.
    private var lastSyncedSearch: CachePayload?

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
        let submittedQuery = query
        hasSearchedThisSession = true
        isLoading = true
        errorMessage = nil
        do {
            let found = try await client.search(submittedQuery)
            guard generation == searchGeneration else { return }
            let synced = CachePayload(models: found, lastSynced: Date(), query: submittedQuery)
            show(synced)
            lastSyncedSearch = synced
            saveCache(synced)
        } catch {
            guard generation == searchGeneration else { return }
            if let lastSyncedSearch, lastSyncedSearch.query == submittedQuery {
                show(lastSyncedSearch)
                errorMessage = "Could not reach Hugging Face. Showing the last synced results."
            } else {
                results = []
                resultsQuery = submittedQuery
                lastSynced = nil
                errorMessage = "Could not reach Hugging Face, and there are no saved results for this search."
            }
        }
        isLoading = false
    }

    private func show(_ search: CachePayload) {
        results = search.models
        resultsQuery = search.query
        lastSynced = search.lastSynced
    }

    /// Runs the first live search of this app session; later visits keep the current results.
    func searchOncePerSession() async {
        guard !hasSearchedThisSession else { return }
        await search()
    }

    private struct CachePayload: Codable {
        var models: [HuggingFaceHubModel]
        var lastSynced: Date
        var query: HuggingFaceHubQuery
    }

    /// Restores the cached search as well, so the filters on screen describe the cached results.
    private func loadCache() {
        guard let data = try? Data(contentsOf: cacheURL),
              let payload = try? JSONDecoder().decode(CachePayload.self, from: data) else { return }
        show(payload)
        query = payload.query
        lastSyncedSearch = payload
    }

    private func saveCache(_ payload: CachePayload) {
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
