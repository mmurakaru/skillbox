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

public enum LocalModelFormat: String, Codable, Sendable {
    case gguf
    case safetensors
    case ollamaBlob
    case unknown
}

/// One AI model stored on this Mac; `digest` groups duplicate copies when the source provides one.
public struct LocalModel: Identifiable, Sendable, Hashable {
    public let id: String
    public var name: String
    public var source: LocalModelSource
    public var path: URL
    public var format: LocalModelFormat
    public var sizeBytes: Int64
    public var digest: String?
    public var modifiedAt: Date?
    /// Content-addressed blobs this model uses, by digest; other models can point at the same blobs.
    public var sharedBlobSizes: [String: Int64]
    /// Files a runtime holds open while the model is loaded; differs from `path` when `path` is a folder.
    public var weightFileURLs: [URL]

    public init(
        id: String,
        name: String,
        source: LocalModelSource,
        path: URL,
        format: LocalModelFormat,
        sizeBytes: Int64,
        digest: String? = nil,
        modifiedAt: Date? = nil,
        sharedBlobSizes: [String: Int64] = [:],
        weightFileURLs: [URL]? = nil
    ) {
        self.id = id
        self.name = name
        self.source = source
        self.path = path
        self.format = format
        self.sizeBytes = sizeBytes
        self.digest = digest
        self.modifiedAt = modifiedAt
        self.sharedBlobSizes = sharedBlobSizes
        self.weightFileURLs = weightFileURLs ?? [path]
    }
}

extension Collection where Element == LocalModel {
    /// Disk space the models use, counting each shared blob once.
    public var totalStorageBytes: Int64 {
        var blobSizes: [String: Int64] = [:]
        var otherBytes: Int64 = 0

        for model in self {
            if model.sharedBlobSizes.isEmpty {
                otherBytes += model.sizeBytes
            } else {
                blobSizes.merge(model.sharedBlobSizes) { first, _ in first }
            }
        }

        return blobSizes.values.reduce(otherBytes, +)
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
