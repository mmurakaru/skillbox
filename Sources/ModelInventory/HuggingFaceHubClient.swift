import Foundation

/// A model listed on the Hugging Face Hub; lab and name come from its `org/name` id.
public struct HuggingFaceHubModel: Sendable, Codable, Identifiable, Equatable {
    public let id: String
    public let downloads: Int?
    public let likes: Int?
    public let pipelineTag: String?
    public let libraryName: String?

    enum CodingKeys: String, CodingKey {
        case id, downloads, likes
        case pipelineTag = "pipeline_tag"
        case libraryName = "library_name"
    }

    public init(id: String, downloads: Int? = nil, likes: Int? = nil, pipelineTag: String? = nil, libraryName: String? = nil) {
        self.id = id
        self.downloads = downloads
        self.likes = likes
        self.pipelineTag = pipelineTag
        self.libraryName = libraryName
    }

    public var lab: String {
        guard let slash = id.firstIndex(of: "/") else { return "" }
        return String(id[..<slash])
    }

    public var name: String {
        guard let slash = id.firstIndex(of: "/") else { return id }
        return String(id[id.index(after: slash)...])
    }

    /// Parameter count parsed from the name, such as "135M", "8B", "8X7B", or "70B"; a hint, not an exact size.
    public var parameterHint: String? {
        guard let match = name.firstMatch(of: /(\d+(?:\.\d+)?(?:[xX]\d+)?)([bBmM])(?:[-_. ]|$)/) else { return nil }
        return String(match.1).uppercased() + String(match.2).uppercased()
    }
}

/// Sort order of Hugging Face Hub model search results.
public enum HuggingFaceHubSort: String, Sendable, Codable, CaseIterable, Identifiable {
    case downloads
    case trending
    case recent

    public var id: String { rawValue }

    public var apiValue: String {
        switch self {
        case .downloads: "downloads"
        case .trending: "trendingScore"
        case .recent: "lastModified"
        }
    }

    public var label: String {
        switch self {
        case .downloads: "Popular"
        case .trending: "Trending"
        case .recent: "Recent"
        }
    }
}

/// Server-side Hub search: free text, lab (author), weight format tag such as `gguf` or `mlx`, and sort.
public struct HuggingFaceHubQuery: Sendable, Equatable, Codable {
    public static let defaultResultLimit = 50
    /// Size filters run on the client, so a filtered search asks for more repos to keep enough matches.
    public static let sizeFilteredResultLimit = 100

    public var search: String
    public var author: String
    public var formatFilter: String?
    public var sort: HuggingFaceHubSort
    public var resultLimit: Int

    public init(
        search: String = "",
        author: String = "",
        formatFilter: String? = nil,
        sort: HuggingFaceHubSort = .downloads,
        resultLimit: Int = HuggingFaceHubQuery.defaultResultLimit
    ) {
        self.search = search
        self.author = author
        self.formatFilter = formatFilter
        self.sort = sort
        self.resultLimit = resultLimit
    }

    private enum CodingKeys: String, CodingKey {
        case search, author, formatFilter, sort, resultLimit
    }

    // Caches written before the limit existed decode with the default limit.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        search = try container.decode(String.self, forKey: .search)
        author = try container.decode(String.self, forKey: .author)
        formatFilter = try container.decodeIfPresent(String.self, forKey: .formatFilter)
        sort = try container.decode(HuggingFaceHubSort.self, forKey: .sort)
        resultLimit = try container.decodeIfPresent(Int.self, forKey: .resultLimit) ?? Self.defaultResultLimit
    }
}

/// Why a Hugging Face Hub search failed.
public enum HuggingFaceHubError: Error, Equatable {
    case unexpectedStatus(Int)
    case invalidRequest
}

/// Searches Hugging Face Hub models.
public protocol HuggingFaceHubSearching: Sendable {
    func search(_ query: HuggingFaceHubQuery) async throws -> [HuggingFaceHubModel]
}

/// Queries the public Hugging Face Hub models API anonymously.
public struct HuggingFaceHubClient: HuggingFaceHubSearching {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func makeRequest(_ query: HuggingFaceHubQuery) throws -> URLRequest {
        guard var components = URLComponents(string: "https://huggingface.co/api/models") else {
            throw HuggingFaceHubError.invalidRequest
        }
        var items = [
            URLQueryItem(name: "limit", value: String(query.resultLimit)),
            URLQueryItem(name: "sort", value: query.sort.apiValue),
            URLQueryItem(name: "direction", value: "-1"),
        ]
        let search = query.search.trimmingCharacters(in: .whitespaces)
        if !search.isEmpty {
            items.append(URLQueryItem(name: "search", value: search))
        }
        let author = query.author.trimmingCharacters(in: .whitespaces)
        if !author.isEmpty {
            items.append(URLQueryItem(name: "author", value: author))
        }
        // The list API ignores `library`; format repos are tagged, and `filter` matches tags.
        if let formatFilter = query.formatFilter, !formatFilter.isEmpty {
            items.append(URLQueryItem(name: "filter", value: formatFilter))
        }
        components.queryItems = items

        guard let url = components.url else { throw HuggingFaceHubError.invalidRequest }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    public func search(_ query: HuggingFaceHubQuery) async throws -> [HuggingFaceHubModel] {
        let (data, response) = try await session.data(for: try makeRequest(query))
        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            throw HuggingFaceHubError.unexpectedStatus(httpResponse.statusCode)
        }
        return try JSONDecoder().decode([HuggingFaceHubModel].self, from: data)
    }
}
