import Testing
import Foundation
import ModelInventory
@testable import Skillbox

@MainActor
struct LocalModelStoreTests {
    private func sampleModels() -> [LocalModel] {
        [
            LocalModel(id: "1", name: "qwen3.5-9b-q4_k_m", source: .openWhispr,
                       path: URL(fileURLWithPath: "/models/a.gguf"), format: .gguf, sizeBytes: 6_000_000_000),
            LocalModel(id: "2", name: "llama-3-8b", source: .ollama,
                       path: URL(fileURLWithPath: "/models/b"), format: .ollamaBlob, sizeBytes: 4_000_000_000),
        ]
    }

    private struct FixedModelScanner: LocalModelScanner {
        let source: LocalModelSource = .custom
        let models: [LocalModel]
        var delaySeconds: Double = 0
        var watchRoots: [URL] { [] }
        func scan() -> [LocalModel] {
            if delaySeconds > 0 { Thread.sleep(forTimeInterval: delaySeconds) }
            return models
        }
    }

    @Test func searchMatchesModelName() {
        let store = LocalModelStore(seedModels: sampleModels())
        store.searchQuery = "qwen"
        #expect(store.filteredModels.map(\.id) == ["1"])
    }

    @Test func searchMatchesSourceName() {
        let store = LocalModelStore(seedModels: sampleModels())
        store.searchQuery = "ollama"
        #expect(store.filteredModels.map(\.id) == ["2"])
    }

    @Test func blankSearchReturnsAllModels() {
        let store = LocalModelStore(seedModels: sampleModels())
        store.searchQuery = "   "
        #expect(store.filteredModels.count == 2)
    }

    @Test func totalBytesSumsAllModels() {
        #expect(LocalModelStore(seedModels: sampleModels()).totalBytes == 10_000_000_000)
    }

    @Test func configureScansEnabledSources() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "local-model-store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data(count: 64).write(to: folder.appending(path: "tiny.gguf"))

        let store = LocalModelStore(makeScanners: { $0.makeScanners(home: folder, applicationSupport: nil) })
        store.configure(LocalModelScanConfiguration(
            ollama: false, huggingFace: false, lmStudio: false, openWhispr: false, appSupport: false,
            customPaths: [folder]
        ))
        await store.rescan().value

        #expect(store.models.map(\.name) == ["tiny"])
        #expect(store.isScanning == false)
    }

    @Test func slowOlderScanDoesNotOverwriteNewerScan() async {
        let newestModels = Array(sampleModels().prefix(1))
        let store = LocalModelStore(makeScanners: { configuration in
            configuration.ollama
                ? [FixedModelScanner(models: [], delaySeconds: 0.3)]
                : [FixedModelScanner(models: newestModels)]
        })
        store.configure(LocalModelScanConfiguration(ollama: true))
        let slowOlderScan = store.rescan()
        store.configure(LocalModelScanConfiguration(ollama: false))
        let newerScan = store.rescan()

        await newerScan.value
        await slowOlderScan.value

        #expect(store.models.map(\.id) == ["1"])
        #expect(store.isScanning == false)
    }

    @Test func copyCountIsOneBeforeDuplicateSearch() {
        let store = LocalModelStore(seedModels: sampleModels())
        #expect(store.copyCount(for: sampleModels()[0]) == 1)
    }

    @Test func duplicateSearchGroupsSharedDigests() async {
        let first = LocalModel(id: "a", name: "a", source: .ollama, path: URL(fileURLWithPath: "/models/a"),
                               format: .ollamaBlob, sizeBytes: 10, digest: "sha256:same")
        let second = LocalModel(id: "b", name: "b", source: .huggingFaceCache, path: URL(fileURLWithPath: "/models/b"),
                                format: .gguf, sizeBytes: 10, digest: "sha256:same")
        let store = LocalModelStore(seedModels: [first, second])

        await store.findDuplicates()?.value

        #expect(store.copyCount(for: first) == 2)
        #expect(store.reclaimableBytes == 10)
    }

    @Test func scanSettingsDefaultToAllSourcesOn() throws {
        let suiteName = "LocalModelScanSettingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(LocalModelScanSettings.configuration(from: defaults) == LocalModelScanConfiguration())

        defaults.set(false, forKey: LocalModelScanSettings.scanOllamaKey)
        defaults.set("/tmp/a, /tmp/b", forKey: LocalModelScanSettings.customPathsKey)
        let configuration = LocalModelScanSettings.configuration(from: defaults)

        #expect(configuration.ollama == false)
        #expect(configuration.huggingFace == true)
        #expect(configuration.customPaths.map(\.path) == ["/tmp/a", "/tmp/b"])
    }
}
