import Foundation

/// Where a local model was found on disk. Each case maps to one scanner.
public enum LocalModelSource: String, Codable, Sendable, CaseIterable {
    case ollama
    case huggingFaceCache
    case lmStudio
    case openWhispr
    case appSupport
    case custom

    public var displayName: String {
        switch self {
        case .ollama: "Ollama"
        case .huggingFaceCache: "Hugging Face"
        case .lmStudio: "LM Studio"
        case .openWhispr: "OpenWhispr"
        case .appSupport: "App Support"
        case .custom: "Custom"
        }
    }
}

/// On-disk weight format of a local model.
public enum LocalModelFormat: String, Codable, Sendable {
    case gguf
    case safetensors
    case ollamaBlob
    case unknown
}

/// One AI model stored on this Mac. `digest` is a content hash or content-addressed blob
/// digest used to find duplicate copies; nil when the source does not provide one.
public struct LocalModel: Identifiable, Sendable, Hashable {
    public let id: String
    public var name: String
    public var source: LocalModelSource
    public var path: URL
    public var format: LocalModelFormat
    public var sizeBytes: Int64
    public var digest: String?
    public var modifiedAt: Date?

    public init(
        id: String,
        name: String,
        source: LocalModelSource,
        path: URL,
        format: LocalModelFormat,
        sizeBytes: Int64,
        digest: String? = nil,
        modifiedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.source = source
        self.path = path
        self.format = format
        self.sizeBytes = sizeBytes
        self.digest = digest
        self.modifiedAt = modifiedAt
    }
}

extension Int64 {
    /// File-size text for a byte count, for example "4.7 GB".
    public var formattedFileSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: self)
    }
}
