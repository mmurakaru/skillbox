import Foundation

/// Scans Ollama's model store; model size is the sum of the blobs its manifest references.
public struct OllamaModelScanner: LocalModelScanner {
    public let source: LocalModelSource = .ollama
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public var watchRoots: [URL] { [root] }

    private struct Manifest: Decodable {
        struct Layer: Decodable {
            let digest: String
            let mediaType: String?
        }
        let config: Layer?
        let layers: [Layer]?
    }

    public func scan() -> [LocalModel] {
        let fileManager = FileManager.default
        let manifestsDirectory = root.appending(path: "manifests")
        let blobsDirectory = root.appending(path: "blobs")

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: manifestsDirectory.path, isDirectory: &isDirectory), isDirectory.boolValue else { return [] }
        guard let enumerator = fileManager.enumerator(
            at: manifestsDirectory,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var results: [LocalModel] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
            guard values?.isRegularFile == true else { continue }
            guard let data = try? Data(contentsOf: url),
                  let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else { continue }

            let layers = manifest.layers ?? []
            let digests = ([manifest.config?.digest] + layers.map(\.digest)).compactMap { $0 }
            var blobSizes: [String: Int64] = [:]
            for digest in digests {
                blobSizes[digest] = blobSize(for: digest, in: blobsDirectory)
            }
            let size = blobSizes.values.reduce(0, +)
            // The weights layer identifies identical models across tags.

            results.append(LocalModel(
                id: "\(source.rawValue):\(url.path)",
                name: modelName(forManifestAt: url, relativeTo: manifestsDirectory),
                source: source,
                path: url,
                format: .ollamaBlob,
                sizeBytes: size,
                modifiedAt: values?.contentModificationDate,
                sharedBlobSizes: blobSizes
            ))
        }
        return results
    }

    /// `manifests/<registry>/<namespace>/<model>/<tag>` becomes `model:tag`, or `namespace/model:tag` outside the library namespace.
    private func modelName(forManifestAt url: URL, relativeTo manifestsDirectory: URL) -> String {
        let components = Array(url.pathComponents.dropFirst(manifestsDirectory.pathComponents.count))
        guard components.count >= 2 else { return url.lastPathComponent }
        let tag = components[components.count - 1]
        let model = components[components.count - 2]
        let namespace = components.count >= 3 ? components[components.count - 3] : nil
        if let namespace, namespace != "library" {
            return "\(namespace)/\(model):\(tag)"
        }
        return "\(model):\(tag)"
    }

    private func blobSize(for digest: String, in blobsDirectory: URL) -> Int64 {
        let blobURL = blobsDirectory.appending(path: digest.replacingOccurrences(of: ":", with: "-"))
        let values = try? blobURL.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }
}
