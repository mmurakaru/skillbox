import Foundation
import CryptoKit

/// A set of byte-identical local models.
public struct DuplicateModelGroup: Identifiable, Sendable {
    public let id: String
    public let models: [LocalModel]

    public init(id: String, models: [LocalModel]) {
        self.id = id
        self.models = models
    }

    public var reclaimableBytes: Int64 {
        guard let size = models.first?.sizeBytes, models.count > 1 else { return 0 }
        return Int64(models.count - 1) * size
    }
}

/// Finds duplicate local models; hashes only same-size files and caches each hash by path, size, and modification date.
public actor DuplicateModelDetector {
    private var contentHashCache: [String: String] = [:]

    public init() {}

    public func findDuplicates(in models: [LocalModel]) -> [DuplicateModelGroup] {
        var modelsByKey: [String: [LocalModel]] = [:]
        var modelsNeedingHash: [LocalModel] = []

        for model in models {
            if let digest = model.digest {
                modelsByKey["digest:\(digest)", default: []].append(model)
            } else {
                modelsNeedingHash.append(model)
            }
        }

        for (_, sameSizeModels) in Dictionary(grouping: modelsNeedingHash, by: \.sizeBytes) where sameSizeModels.count > 1 {
            for model in sameSizeModels {
                guard let hash = contentHash(for: model) else { continue }
                modelsByKey["hash:\(hash)", default: []].append(model)
            }
        }

        return modelsByKey
            .filter { $0.value.count > 1 }
            .map { DuplicateModelGroup(id: $0.key, models: $0.value.sorted { $0.path.path < $1.path.path }) }
            .sorted { $0.reclaimableBytes > $1.reclaimableBytes }
    }

    private func contentHash(for model: LocalModel) -> String? {
        let modificationTime = model.modifiedAt?.timeIntervalSince1970 ?? 0
        let cacheKey = "\(model.path.path)|\(model.sizeBytes)|\(modificationTime)"
        if let cached = contentHashCache[cacheKey] { return cached }

        guard let handle = try? FileHandle(forReadingFrom: model.path) else { return nil }
        defer { try? handle.close() }

        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        contentHashCache[cacheKey] = digest
        return digest
    }
}
