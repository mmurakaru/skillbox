import Foundation
import CryptoKit

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
            let snapshotsDirectory = repositoryDirectory.appending(path: "snapshots")
            results.append(LocalModel(
                id: "\(source.rawValue):\(repositoryDirectory.path)",
                name: repositoryID,
                source: source,
                path: repositoryDirectory,
                format: detectFormat(in: snapshotsDirectory),
                sizeBytes: totals.size,
                digest: totals.contentIdentity,
                modifiedAt: modified?.contentModificationDate,
                weightFileURLs: weightBlobs(in: snapshotsDirectory)
            ))
        }
        return results
    }

    /// Blob names are content hashes, so the full set of names and sizes identifies byte-identical repos.
    private func blobTotals(in blobsDirectory: URL) -> (size: Int64, contentIdentity: String?) {
        guard let blobs = try? FileManager.default.contentsOfDirectory(
            at: blobsDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return (0, nil) }

        var total: Int64 = 0
        var blobEntries: [String] = []
        for blob in blobs {
            let values = try? blob.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            let size = Int64(values?.fileSize ?? 0)
            total += size
            blobEntries.append("\(blob.lastPathComponent):\(size)")
        }
        guard !blobEntries.isEmpty else { return (0, nil) }
        let identity = SHA256.hash(data: Data(blobEntries.sorted().joined(separator: "\n").utf8))
            .map { String(format: "%02x", $0) }.joined()
        return (total, "blobs:\(identity)")
    }

    /// Snapshot entries are symlinks into `blobs/`, and runtimes hold the blob open, so return the link targets.
    private func weightBlobs(in snapshotsDirectory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: snapshotsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var blobs: [URL] = []
        for case let url as URL in enumerator where ["gguf", "safetensors"].contains(url.pathExtension.lowercased()) {
            let blob = url.resolvingSymlinksInPath()
            if !blobs.contains(blob) { blobs.append(blob) }
        }
        return blobs
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
