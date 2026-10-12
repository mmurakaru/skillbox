import Foundation

/// Finds the local models of one source. Best-effort: a missing directory yields no models, never an error.
public protocol LocalModelScanner: Sendable {
    var source: LocalModelSource { get }
    /// Directories whose changes should trigger a rescan.
    var watchRoots: [URL] { get }
    func scan() -> [LocalModel]
}

/// Finds `.gguf` and `.safetensors` weight files for OpenWhispr, LM Studio, Application Support, and custom folders.
public struct FlatFileModelScanner: LocalModelScanner {
    public let source: LocalModelSource
    public let roots: [URL]

    public init(source: LocalModelSource, roots: [URL]) {
        self.source = source
        self.roots = roots
    }

    public var watchRoots: [URL] { roots }

    private static let weightFileExtensions: Set<String> = ["gguf", "safetensors"]

    public func scan() -> [LocalModel] {
        let fileManager = FileManager.default
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        var results: [LocalModel] = []

        for root in roots {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else { continue }
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            ) else { continue }

            for case let url as URL in enumerator {
                if Task.isCancelled { return results }
                let fileExtension = url.pathExtension.lowercased()
                guard Self.weightFileExtensions.contains(fileExtension) else { continue }
                let values = try? url.resourceValues(forKeys: Set(keys))
                if values?.isRegularFile == false { continue }
                results.append(LocalModel(
                    id: "\(source.rawValue):\(url.path)",
                    name: url.deletingPathExtension().lastPathComponent,
                    source: source,
                    path: url,
                    format: fileExtension == "safetensors" ? .safetensors : .gguf,
                    sizeBytes: Int64(values?.fileSize ?? 0),
                    modifiedAt: values?.contentModificationDate
                ))
            }
        }
        return results
    }
}
