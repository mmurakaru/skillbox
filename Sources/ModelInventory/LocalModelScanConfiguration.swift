import Foundation

/// Which local model sources to scan, plus user-added folders. Mirrors the Local models settings.
public struct LocalModelScanConfiguration: Equatable, Sendable {
    public var ollama: Bool
    public var huggingFace: Bool
    public var lmStudio: Bool
    public var openWhispr: Bool
    public var appSupport: Bool
    public var customPaths: [URL]

    public init(
        ollama: Bool = true,
        huggingFace: Bool = true,
        lmStudio: Bool = true,
        openWhispr: Bool = true,
        appSupport: Bool = true,
        customPaths: [URL] = []
    ) {
        self.ollama = ollama
        self.huggingFace = huggingFace
        self.lmStudio = lmStudio
        self.openWhispr = openWhispr
        self.appSupport = appSupport
        self.customPaths = customPaths
    }

    /// Drops the home folder and `/`, since walking either for weight files would read most of the disk.
    public static func parseCustomPaths(_ rawPaths: String, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        let refusedPaths: Set<String> = ["/", home.standardizedFileURL.path]

        return rawPaths.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath).standardizedFileURL }
            .filter { !refusedPaths.contains($0.path) }
    }

    /// Builds one scanner per enabled source, rooted at the given home and Application Support folders.
    public func makeScanners(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        applicationSupport: URL? = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    ) -> [any LocalModelScanner] {
        var scanners: [any LocalModelScanner] = []

        if ollama {
            scanners.append(OllamaModelScanner(root: home.appending(path: ".ollama/models")))
        }

        if huggingFace {
            scanners.append(HuggingFaceCacheScanner(root: HuggingFaceCacheScanner.defaultRoot(home: home)))
        }

        if openWhispr {
            scanners.append(
                FlatFileModelScanner(
                    source: .openWhispr,
                    roots: [
                        home.appending(path: ".cache/openwhispr/models")
                    ]))
        }

        if lmStudio {
            scanners.append(
                FlatFileModelScanner(
                    source: .lmStudio,
                    roots: [
                        home.appending(path: ".lmstudio/models"),
                        home.appending(path: ".cache/lm-studio"),
                    ]))
        }

        if appSupport, let applicationSupport {
            scanners.append(
                FlatFileModelScanner(
                    source: .appSupport,
                    roots: Self.applicationSupportModelFolders(in: applicationSupport)
                ))
        }

        if !customPaths.isEmpty {
            scanners.append(FlatFileModelScanner(source: .custom, roots: customPaths))
        }

        return scanners
    }

    /// Existing `<Application Support>/<app>/models` folders.
    public static func applicationSupportModelFolders(in applicationSupport: URL) -> [URL] {
        let fileManager = FileManager.default

        guard
            let entries = try? fileManager.contentsOfDirectory(
                at: applicationSupport,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        else { return [] }

        return
            entries
            .map { $0.appending(path: "models") }
            .filter { url in
                var isDirectory: ObjCBool = false

                return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
            }
    }
}
