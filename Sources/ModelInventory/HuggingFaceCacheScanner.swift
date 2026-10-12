import Foundation

/// Scans the Hugging Face Hub cache; size sums the blobs because snapshots only symlink into them.
public struct HuggingFaceCacheScanner: LocalModelScanner {
    public let source: LocalModelSource = .huggingFaceCache
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public var watchRoots: [URL] { [root] }

    /// Cache root after `HF_HUB_CACHE` and `HF_HOME` overrides.
    public static func defaultRoot(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        func expandTilde(_ path: String) -> URL { URL(fileURLWithPath: (path as NSString).expandingTildeInPath) }
        if let hubCache = environment["HF_HUB_CACHE"], !hubCache.isEmpty {
            return expandTilde(hubCache)
        }
        if let huggingFaceHome = environment["HF_HOME"], !huggingFaceHome.isEmpty {
            return expandTilde(huggingFaceHome).appending(path: "hub")
        }
        return home.appending(path: ".cache/huggingface/hub")
    }

    public func scan() -> [LocalModel] {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else { return [] }
        guard let entries = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var results: [LocalModel] = []
        for repositoryDirectory in entries where repositoryDirectory.lastPathComponent.hasPrefix("models--") {
            let repositoryID = repositoryDirectory.lastPathComponent
                .dropFirst("models--".count)
                .replacingOccurrences(of: "--", with: "/")

            let totals = blobTotals(in: repositoryDirectory.appending(path: "blobs"))
            guard totals.size > 0 else { continue }

            let modified = try? repositoryDirectory.resourceValues(forKeys: [.contentModificationDateKey])
            results.append(LocalModel(
                id: "\(source.rawValue):\(repositoryDirectory.path)",
                name: repositoryID,
                source: source,
                path: repositoryDirectory,
                format: detectFormat(in: repositoryDirectory.appending(path: "snapshots")),
                sizeBytes: totals.size,
                digest: totals.largestBlobName,
                modifiedAt: modified?.contentModificationDate
            ))
        }
        return results
    }

    /// The largest blob name is a stable duplicate key across caches.
    private func blobTotals(in blobsDirectory: URL) -> (size: Int64, largestBlobName: String?) {
        guard let blobs = try? FileManager.default.contentsOfDirectory(
            at: blobsDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return (0, nil) }

        var total: Int64 = 0
        var largestSize: Int64 = -1
        var largestName: String?
        for blob in blobs {
            let values = try? blob.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            let size = Int64(values?.fileSize ?? 0)
            total += size
            if size > largestSize {
                largestSize = size
                largestName = blob.lastPathComponent
            }
        }
        return (total, largestName)
    }

    private func detectFormat(in snapshotsDirectory: URL) -> LocalModelFormat {
        guard let enumerator = FileManager.default.enumerator(
            at: snapshotsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return .unknown }
        var sawSafetensors = false
        for case let url as URL in enumerator {
            switch url.pathExtension.lowercased() {
            case "gguf": return .gguf
            case "safetensors": sawSafetensors = true
            default: break
            }
        }
        return sawSafetensors ? .safetensors : .unknown
    }
}
