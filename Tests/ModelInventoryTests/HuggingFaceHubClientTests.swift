import Testing
import Foundation
@testable import ModelInventory

struct HuggingFaceHubClientTests {
    private func queryItems(_ query: HuggingFaceHubQuery) -> [String: String] {
        let url = HuggingFaceHubClient().makeRequest(query).url!
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    @Test func requestIncludesSearchAuthorLibraryAndSort() {
        let request = HuggingFaceHubClient().makeRequest(HuggingFaceHubQuery(search: "qwen", author: "Qwen", library: "gguf", sort: .recent))
        #expect(request.url?.absoluteString.hasPrefix("https://huggingface.co/api/models?") == true)
        #expect(queryItems(HuggingFaceHubQuery(search: "qwen", author: "Qwen", library: "gguf", sort: .recent)) == [
            "limit": "50", "sort": "lastModified", "direction": "-1",
            "search": "qwen", "author": "Qwen", "library": "gguf",
        ])
    }

    @Test func requestOmitsBlankFilters() {
        #expect(queryItems(HuggingFaceHubQuery(search: "  ", author: "")) == ["limit": "50", "sort": "downloads", "direction": "-1"])
    }

    @Test func requestIsAnonymous() {
        #expect(HuggingFaceHubClient().makeRequest(HuggingFaceHubQuery()).value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func sortAPIValues() {
        #expect(HuggingFaceHubSort.allCases.map(\.apiValue) == ["downloads", "trendingScore", "lastModified"])
    }

    @Test func decodesListIgnoringUnknownFields() throws {
        let json = Data("""
        [
          {"_id":"abc","id":"Qwen/Qwen3-8B","likes":10,"downloads":12345,
           "pipeline_tag":"text-generation","library_name":"transformers","tags":["x"]},
          {"_id":"def","id":"mistralai/Mixtral-8x7B-Instruct-v0.1","downloads":999}
        ]
        """.utf8)

        let models = try JSONDecoder().decode([HuggingFaceHubModel].self, from: json)

        #expect(models.map(\.lab) == ["Qwen", "mistralai"])
        #expect(models.first?.name == "Qwen3-8B")
        #expect(models.first?.libraryName == "transformers")
        #expect(models.map(\.parameterHint) == ["8B", "8X7B"])
    }

    @Test func parameterHintIsNilWithoutSize() {
        #expect(HuggingFaceHubModel(id: "sentence-transformers/all-MiniLM-L6-v2").parameterHint == nil)
    }
}
