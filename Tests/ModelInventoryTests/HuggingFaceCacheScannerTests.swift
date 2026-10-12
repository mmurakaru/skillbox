import Testing
import Foundation
@testable import ModelInventory

struct HuggingFaceCacheScannerTests {
    private func makeRepository(
        in directory: ModelInventoryTestDirectory,
        folder: String,
        blobs: [(name: String, bytes: Int)],
        snapshotFile: String?
    ) throws {
        for blob in blobs {
            try directory.writeFile("\(folder)/blobs/\(blob.name)", bytes: blob.bytes)
        }
        if blobs.isEmpty {
            try FileManager.default.createDirectory(
                at: directory.url.appending(path: "\(folder)/blobs"),
                withIntermediateDirectories: true
            )
        }
        if let snapshotFile {
            try directory.writeFile("\(folder)/snapshots/abc123/\(snapshotFile)", bytes: 1)
        }
    }

    @Test func readsRepositoryIDSizeAndFormat() throws {
        let hub = try ModelInventoryTestDirectory()
        try makeRepository(in: hub, folder: "models--Qwen--Qwen3-8B",
                           blobs: [("aaa", 1000), ("bbb", 4000)], snapshotFile: "model.safetensors")

        let models = HuggingFaceCacheScanner(root: hub.url).scan()

        #expect(models.count == 1)
        #expect(models.first?.name == "Qwen/Qwen3-8B")
        #expect(models.first?.source == .huggingFaceCache)
        #expect(models.first?.sizeBytes == 5000)
        #expect(models.first?.digest == "bbb")
        #expect(models.first?.format == .safetensors)
    }

    @Test func detectsGGUFFormat() throws {
        let hub = try ModelInventoryTestDirectory()
        try makeRepository(in: hub, folder: "models--Example--Foo-GGUF", blobs: [("x", 10)], snapshotFile: "foo.Q4_K_M.gguf")
        #expect(HuggingFaceCacheScanner(root: hub.url).scan().first?.format == .gguf)
    }

    @Test func ignoresNonRepositoryFoldersAndEmptyRepositories() throws {
        let hub = try ModelInventoryTestDirectory()
        try makeRepository(in: hub, folder: "models--Empty--Repo", blobs: [], snapshotFile: nil)
        try FileManager.default.createDirectory(at: hub.url.appending(path: "version-folder"), withIntermediateDirectories: true)
        #expect(HuggingFaceCacheScanner(root: hub.url).scan().isEmpty)
    }

    @Test func defaultRootHonorsEnvironmentOverrides() {
        let home = URL(fileURLWithPath: "/tmp/example-home")
        #expect(HuggingFaceCacheScanner.defaultRoot(environment: [:], home: home).path == "/tmp/example-home/.cache/huggingface/hub")
        #expect(HuggingFaceCacheScanner.defaultRoot(environment: ["HF_HOME": "/data/hf"], home: home).path == "/data/hf/hub")
        #expect(HuggingFaceCacheScanner.defaultRoot(environment: ["HF_HUB_CACHE": "/data/hub"], home: home).path == "/data/hub")
    }
}
