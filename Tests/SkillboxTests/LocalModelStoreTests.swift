import Foundation
import ModelInventory
import Testing

@testable import Skillbox

@MainActor
struct LocalModelStoreTests {
    private func sampleModels() -> [LocalModel] {
        [
            LocalModel(
                id: "1", name: "qwen3.5-9b-q4_k_m", source: .openWhispr,
                path: URL(fileURLWithPath: "/models/a.gguf"), format: .gguf, sizeBytes: 6_000_000_000),
            LocalModel(
                id: "2", name: "llama-3-8b", source: .ollama,
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

    private actor RecordingRuntimeMonitor: ModelRuntimeMonitoring {
        var states: [String: ModelRuntimeState]
        private(set) var stopRequests: [ModelStopTarget] = []

        init(states: [String: ModelRuntimeState]) { self.states = states }

        func runtimeStates(for models: [LocalModel]) async -> [String: ModelRuntimeState] { states }

        func stop(_ target: ModelStopTarget, weightFileURLs: [URL]) async {
            stopRequests.append(target)
            states = [:]
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

        store.configure(
            LocalModelScanConfiguration(
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

    @Test func modelFolderCreatedAfterConfigureIsScannedAutomatically() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "local-model-watch-\(UUID().uuidString)")

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let laterFolder = root.appending(path: "later/models")

        let store = LocalModelStore(makeScanners: { $0.makeScanners(home: root, applicationSupport: nil) })

        store.configure(
            LocalModelScanConfiguration(
                ollama: false, huggingFace: false, lmStudio: false, openWhispr: false, appSupport: false,
                customPaths: [laterFolder]
            ))
        await store.rescan().value
        #expect(store.models.isEmpty)
        #expect(!store.watchModelFoldersCreatedSinceLastCheck())
        try FileManager.default.createDirectory(at: laterFolder, withIntermediateDirectories: true)
        try Data(count: 32).write(to: laterFolder.appending(path: "arrived.gguf"))

        #expect(store.watchModelFoldersCreatedSinceLastCheck())
        try await waitUntil { store.models.map(\.name) == ["arrived"] }

        try Data(count: 32).write(to: laterFolder.appending(path: "second.gguf"))
        try await waitUntil { store.models.count == 2 }
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)

        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(condition())
    }

    @Test func totalBytesCountsSharedOllamaBlobsOnce() {
        let blobs: [String: Int64] = ["sha256:weights": 4_000, "sha256:config": 10]
        let tag = LocalModel(
            id: "ollama:a", name: "a:latest", source: .ollama, path: URL(fileURLWithPath: "/models/a"),
            format: .ollamaBlob, sizeBytes: 4_010, sharedBlobSizes: blobs)
        let copiedTag = LocalModel(
            id: "ollama:b", name: "b:latest", source: .ollama, path: URL(fileURLWithPath: "/models/b"),
            format: .ollamaBlob, sizeBytes: 4_010, sharedBlobSizes: blobs)
        let file = LocalModel(
            id: "custom:c", name: "c", source: .custom, path: URL(fileURLWithPath: "/models/c.gguf"),
            format: .gguf, sizeBytes: 500)

        #expect(LocalModelStore(seedModels: [tag, copiedTag, file]).totalBytes == 4_510)
    }

    @Test func copyCountIsOneBeforeDuplicateSearch() {
        let store = LocalModelStore(seedModels: sampleModels())

        #expect(store.copyCount(for: sampleModels()[0]) == 1)
    }

    @Test func duplicateSearchGroupsSharedDigests() async {
        let first = LocalModel(
            id: "a", name: "a", source: .ollama, path: URL(fileURLWithPath: "/models/a"),
            format: .ollamaBlob, sizeBytes: 10, digest: "sha256:same")
        let second = LocalModel(
            id: "b", name: "b", source: .huggingFaceCache, path: URL(fileURLWithPath: "/models/b"),
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

    @Test func runtimeRefreshAndStopUnloadTheModel() async {
        let target = ModelStopTarget.ollama(modelName: "llama-3-8b")
        let monitor = RecordingRuntimeMonitor(states: ["2": ModelRuntimeState(stopTarget: target, hostName: "Ollama")])
        let store = LocalModelStore(runtimeMonitor: monitor, seedModels: sampleModels())

        await store.refreshRuntimeStates()
        #expect(store.runtimeState(for: sampleModels()[1])?.stopTarget == target)

        await store.stop(sampleModels()[1])
        #expect(await monitor.stopRequests == [target])
        #expect(store.runtimeState(for: sampleModels()[1]) == nil)
    }

    @Test func stopIgnoresModelsWithoutStopTarget() async {
        let monitor = RecordingRuntimeMonitor(states: ["1": ModelRuntimeState(stopTarget: nil, hostName: "OtherApp")])
        let store = LocalModelStore(runtimeMonitor: monitor, seedModels: sampleModels())

        await store.refreshRuntimeStates()

        await store.stop(sampleModels()[0])

        #expect(await monitor.stopRequests.isEmpty)
    }

    @Test func moveToTrashRemovesModelAndItsDuplicateGroup() async throws {
        let trashable = LocalModel(
            id: "t", name: "copy", source: .custom, path: URL(fileURLWithPath: "/models/copy.gguf"),
            format: .gguf, sizeBytes: 8, digest: "same")
        let twin = LocalModel(
            id: "u", name: "twin", source: .custom, path: URL(fileURLWithPath: "/models/twin.gguf"),
            format: .gguf, sizeBytes: 8, digest: "same")
        var trashedPaths: [String] = []
        let store = LocalModelStore(moveItemToTrash: { trashedPaths.append($0.path) }, seedModels: [trashable, twin])

        await store.findDuplicates()?.value
        #expect(store.copyCount(for: twin) == 2)

        try store.moveToTrash(trashable)

        #expect(trashedPaths == ["/models/copy.gguf"])
        #expect(store.models.map(\.id) == ["u"])
        #expect(store.copyCount(for: twin) == 1)
        #expect(store.reclaimableBytes == 0)
    }

    @Test func failedMoveToTrashKeepsTheModel() {
        struct TrashFailure: Error {}
        let store = LocalModelStore(moveItemToTrash: { _ in throw TrashFailure() }, seedModels: sampleModels())

        #expect(throws: TrashFailure.self) { try store.moveToTrash(sampleModels()[0]) }
        #expect(store.models.count == 2)
    }

    @Test func moveToTrashRefusesSharedOllamaBlobs() {
        let store = LocalModelStore(seedModels: sampleModels())

        #expect(throws: LocalModelTrashError.notTrashable("llama-3-8b")) {
            try store.moveToTrash(sampleModels()[1])
        }
        #expect(store.models.count == 2)
    }
}
