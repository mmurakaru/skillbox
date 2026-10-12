import Testing
import Foundation
import ModelInventory
@testable import Skillbox

@MainActor
struct ModelExplorerStoreTests {
    private struct StubHubSearch: HuggingFaceHubSearching {
        let result: Result<[HuggingFaceHubModel], HuggingFaceHubError>
        var delaySeconds: Double = 0
        func search(_ query: HuggingFaceHubQuery) async throws -> [HuggingFaceHubModel] {
            if delaySeconds > 0 { try await Task.sleep(for: .seconds(delaySeconds)) }
            return try result.get()
        }
    }

    /// Answers each search with the result for its search text.
    private struct QueryEchoSearch: HuggingFaceHubSearching {
        func search(_ query: HuggingFaceHubQuery) async throws -> [HuggingFaceHubModel] {
            if query.search == "slow" { try await Task.sleep(for: .milliseconds(300)) }
            return [HuggingFaceHubModel(id: "org/\(query.search)")]
        }
    }

    private func temporaryCacheURL() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "model-explorer-\(UUID().uuidString)/cache.json")
    }

    @Test func successfulSearchStoresResultsAndTimestamp() async {
        let cacheURL = temporaryCacheURL()
        defer { try? FileManager.default.removeItem(at: cacheURL.deletingLastPathComponent()) }
        let store = ModelExplorerStore(client: StubHubSearch(result: .success([HuggingFaceHubModel(id: "Qwen/Qwen3-8B")])), cacheURL: cacheURL)

        await store.search()

        #expect(store.results.map(\.id) == ["Qwen/Qwen3-8B"])
        #expect(store.lastSynced != nil)
        #expect(store.errorMessage == nil)
        #expect(store.isLoading == false)
    }

    @Test func failedSearchKeepsCachedResultsAndShowsError() async {
        let cacheURL = temporaryCacheURL()
        defer { try? FileManager.default.removeItem(at: cacheURL.deletingLastPathComponent()) }
        await ModelExplorerStore(client: StubHubSearch(result: .success([HuggingFaceHubModel(id: "Qwen/Qwen3-8B")])), cacheURL: cacheURL).search()

        let offline = ModelExplorerStore(client: StubHubSearch(result: .failure(.unexpectedStatus(503))), cacheURL: cacheURL)
        #expect(offline.results.map(\.id) == ["Qwen/Qwen3-8B"])
        await offline.search()

        #expect(offline.results.map(\.id) == ["Qwen/Qwen3-8B"])
        #expect(offline.errorMessage == "Could not reach Hugging Face. Showing the last synced results.")
    }

    @Test func cachedResultsComeBackWithTheirSearch() async {
        let cacheURL = temporaryCacheURL()
        defer { try? FileManager.default.removeItem(at: cacheURL.deletingLastPathComponent()) }
        let online = ModelExplorerStore(client: QueryEchoSearch(), cacheURL: cacheURL)
        online.query.search = "qwen"
        await online.search()

        let relaunched = ModelExplorerStore(client: StubHubSearch(result: .failure(.unexpectedStatus(503))), cacheURL: cacheURL)

        #expect(relaunched.query.search == "qwen")
        #expect(relaunched.results.map(\.id) == ["org/qwen"])
    }

    @Test func offlineSearchForAnotherQueryShowsNoStaleResults() async {
        let cacheURL = temporaryCacheURL()
        defer { try? FileManager.default.removeItem(at: cacheURL.deletingLastPathComponent()) }
        let online = ModelExplorerStore(client: QueryEchoSearch(), cacheURL: cacheURL)
        online.query.search = "qwen"
        await online.search()

        let offline = ModelExplorerStore(client: StubHubSearch(result: .failure(.unexpectedStatus(503))), cacheURL: cacheURL)
        offline.query.search = "llama"
        await offline.search()

        #expect(offline.results.isEmpty)
        #expect(offline.errorMessage == "Could not reach Hugging Face, and there are no saved results for this search.")
    }

    @Test func sizeBucketFiltersDisplayedResults() async {
        let cacheURL = temporaryCacheURL()
        defer { try? FileManager.default.removeItem(at: cacheURL.deletingLastPathComponent()) }
        let store = ModelExplorerStore(client: StubHubSearch(result: .success([
            HuggingFaceHubModel(id: "Qwen/Qwen3-4B"),
            HuggingFaceHubModel(id: "meta/Llama-3-8B"),
            HuggingFaceHubModel(id: "meta/Llama-3-70B"),
        ])), cacheURL: cacheURL)
        await store.search()

        #expect(store.displayedResults.count == 3)
        store.sizeBucket = .small
        #expect(store.displayedResults.map(\.name) == ["Qwen3-4B"])
        store.sizeBucket = .extraLarge
        #expect(store.displayedResults.map(\.name) == ["Llama-3-70B"])
    }

    @Test func slowOlderSearchDoesNotReplaceNewerResults() async {
        let cacheURL = temporaryCacheURL()
        defer { try? FileManager.default.removeItem(at: cacheURL.deletingLastPathComponent()) }
        let store = ModelExplorerStore(client: QueryEchoSearch(), cacheURL: cacheURL)

        store.query.search = "slow"
        let slowSearch = Task { await store.search() }
        try? await Task.sleep(for: .milliseconds(50))
        store.query.search = "fast"
        await store.search()
        await slowSearch.value

        #expect(store.results.map(\.id) == ["org/fast"])
        #expect(store.isLoading == false)
    }

    @Test func searchesLiveOnlyOncePerSessionEvenWithCache() async {
        let cacheURL = temporaryCacheURL()
        defer { try? FileManager.default.removeItem(at: cacheURL.deletingLastPathComponent()) }
        await ModelExplorerStore(client: StubHubSearch(result: .success([HuggingFaceHubModel(id: "org/cached")])), cacheURL: cacheURL).search()

        let store = ModelExplorerStore(client: QueryEchoSearch(), cacheURL: cacheURL)
        store.query.search = "live"
        await store.searchOncePerSession()
        #expect(store.results.map(\.id) == ["org/live"])

        store.query.search = "again"
        await store.searchOncePerSession()
        #expect(store.results.map(\.id) == ["org/live"])
    }
}
