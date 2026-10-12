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

    /// Parameter count parsed from the name, such as "8B", "8X7B", or "70B"; a hint, not an exact size.
    public var parameterHint: String? {
        guard let match = name.firstMatch(of: /(\d+(?:\.\d+)?(?:x\d+)?)[bB](?:[-_. ]|$)/) else { return nil }
        return String(match.1).uppercased() + "B"
    }
}

/// Sort order of Hugging Face Hub model search results.
public enum HuggingFaceHubSort: String, Sendable, CaseIterable, Identifiable {
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

/// Server-side Hub search: free text, lab (author), format library, and sort.
public struct HuggingFaceHubQuery: Sendable, Equatable {
    public var search: String
    public var author: String
    public var library: String?
    public var sort: HuggingFaceHubSort

    public init(search: String = "", author: String = "", library: String? = nil, sort: HuggingFaceHubSort = .downloads) {
        self.search = search
        self.author = author
        self.library = library
        self.sort = sort
    }
}

/// Why a Hugging Face Hub search failed.
public enum HuggingFaceHubError: Error, Equatable {
    case unexpectedStatus(Int)
}

/// Searches Hugging Face Hub models.
public protocol HuggingFaceHubSearching: Sendable {
    func search(_ query: HuggingFaceHubQuery) async throws -> [HuggingFaceHubModel]
}

/// Queries the public Hugging Face Hub models API anonymously.
public struct HuggingFaceHubClient: HuggingFaceHubSearching {
    public static let resultLimit = 50
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func makeRequest(_ query: HuggingFaceHubQuery) -> URLRequest {
        var components = URLComponents(string: "https://huggingface.co/api/models")!
        var items = [
            URLQueryItem(name: "limit", value: String(Self.resultLimit)),
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
        if let library = query.library, !library.isEmpty {
            items.append(URLQueryItem(name: "library", value: library))
        }
        components.queryItems = items

        var request = URLRequest(url: components.url!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    public func search(_ query: HuggingFaceHubQuery) async throws -> [HuggingFaceHubModel] {
        let (data, response) = try await session.data(for: makeRequest(query))
        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            throw HuggingFaceHubError.unexpectedStatus(httpResponse.statusCode)
        }
        return try JSONDecoder().decode([HuggingFaceHubModel].self, from: data)
    }
}
