import Foundation
import Testing

@testable import ModelInventory

struct OllamaModelScannerTests {
    private func writeBlob(_ digest: String, bytes: Int, in store: ModelInventoryTestDirectory) throws {
        try store.writeFile("blobs/\(digest.replacingOccurrences(of: ":", with: "-"))", bytes: bytes)
    }

    private func writeManifest(_ path: String, json: String, in store: ModelInventoryTestDirectory) throws {
        try store.writeFile("manifests/\(path)", contents: Data(json.utf8))
    }

    @Test func readsManifestAndSumsBlobSizes() throws {
        let store = try ModelInventoryTestDirectory()

        try writeBlob("sha256:config", bytes: 100, in: store)
        try writeBlob("sha256:weights", bytes: 5000, in: store)
        try writeManifest(
            "registry.ollama.ai/library/llama3/8b",
            json: """
                {
                  "config": {"digest": "sha256:config", "mediaType": "application/vnd.ollama.image.config"},
                  "layers": [{"digest": "sha256:weights", "mediaType": "application/vnd.ollama.image.model"}]
                }
                """, in: store)

        let models = OllamaModelScanner(root: store.url).scan()

        #expect(models.count == 1)
        #expect(models.first?.name == "llama3:8b")
        #expect(models.first?.source == .ollama)
        #expect(models.first?.sizeBytes == 5100)
        #expect(models.first?.digest == nil)
        #expect(models.first?.format == .ollamaBlob)
    }

    @Test func keepsNamespaceOutsideTheLibrary() throws {
        let store = try ModelInventoryTestDirectory()

        try writeBlob("sha256:w", bytes: 10, in: store)
        try writeManifest(
            "hf.co/user/mymodel/q4",
            json: """
                {"layers": [{"digest": "sha256:w", "mediaType": "application/vnd.ollama.image.model"}]}
                """, in: store)

        #expect(OllamaModelScanner(root: store.url).scan().map(\.name) == ["user/mymodel:q4"])
    }

    @Test func missingStoreYieldsNothing() throws {
        let store = try ModelInventoryTestDirectory()

        #expect(OllamaModelScanner(root: store.url.appending(path: "missing")).scan().isEmpty)
    }
}
