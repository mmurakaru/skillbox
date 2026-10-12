import Foundation
import Testing

@testable import ModelInventory

struct HuggingFaceHubClientTests {
    private func queryItems(_ query: HuggingFaceHubQuery) throws -> [String: String] {
        let url = try #require(try HuggingFaceHubClient().makeRequest(query).url)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    @Test func requestIncludesSearchAuthorFormatTagAndSort() throws {
        let request = try HuggingFaceHubClient().makeRequest(
            HuggingFaceHubQuery(search: "qwen", author: "Qwen", formatFilter: "gguf", sort: .recent))

        #expect(request.url?.absoluteString.hasPrefix("https://huggingface.co/api/models?") == true)
        #expect(
            try queryItems(HuggingFaceHubQuery(search: "qwen", author: "Qwen", formatFilter: "gguf", sort: .recent)) == [
                "limit": "50", "sort": "lastModified", "direction": "-1",
                "search": "qwen", "author": "Qwen", "filter": "gguf",
            ])
    }

    @Test func requestOmitsBlankFilters() throws {
        #expect(try queryItems(HuggingFaceHubQuery(search: "  ", author: "")) == ["limit": "50", "sort": "downloads", "direction": "-1"])
    }

    @Test func requestIsAnonymous() throws {
        #expect(try HuggingFaceHubClient().makeRequest(HuggingFaceHubQuery()).value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func requestSendsTheQueryResultLimit() throws {
        #expect(try queryItems(HuggingFaceHubQuery(resultLimit: HuggingFaceHubQuery.sizeFilteredResultLimit))["limit"] == "100")
    }

    @Test func queryCachedWithoutALimitDecodesWithTheDefault() throws {
        let cached = Data(#"{"search":"qwen","author":"","sort":"downloads"}"#.utf8)

        #expect(try JSONDecoder().decode(HuggingFaceHubQuery.self, from: cached).resultLimit == HuggingFaceHubQuery.defaultResultLimit)
    }

    @Test func sortAPIValues() {
        #expect(HuggingFaceHubSort.allCases.map(\.apiValue) == ["downloads", "trendingScore", "lastModified"])
    }

    @Test func decodesListIgnoringUnknownFields() throws {
        let json = Data(
            """
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

    @Test func parameterHintReadsMillionsAndUppercaseMixtures() {
        #expect(HuggingFaceHubModel(id: "org/SmolLM2-135M").parameterHint == "135M")
        #expect(HuggingFaceHubModel(id: "org/gemma-3-270m-it").parameterHint == "270M")
        #expect(HuggingFaceHubModel(id: "org/Mixtral-8X7B-v0.1").parameterHint == "8X7B")
    }

    @Test func parameterHintIsNilWithoutSize() {
        #expect(HuggingFaceHubModel(id: "sentence-transformers/all-MiniLM-L6-v2").parameterHint == nil)
    }
}
