import Foundation
import Testing

@testable import ModelInventory

struct HuggingFaceHubModelHandoffTests {
    private func local(_ name: String, _ source: LocalModelSource) -> LocalModel {
        LocalModel(
            id: "\(source.rawValue):\(name)", name: name, source: source,
            path: URL(fileURLWithPath: "/models/\(name)"), format: .gguf, sizeBytes: 1)
    }

    private func installed(_ hubID: String, _ localModels: [LocalModel]) -> Bool {
        HuggingFaceHubModelHandoff.isInstalled(HuggingFaceHubModel(id: hubID), localModels: localModels)
    }

    @Test func matchesLocalFileNamedAfterTheRepository() {
        #expect(installed("Qwen/Qwen3.5-9B", [local("Qwen_Qwen3.5-9B-Q4_K_M", .lmStudio)]))
        #expect(installed("org/Model-8B-GGUF", [local("Model-8B.Q8_0", .custom)]))
    }

    @Test func matchesHuggingFaceCacheRepositoryExactly() {
        #expect(installed("Qwen/Qwen3-8B", [local("Qwen/Qwen3-8B", .huggingFaceCache)]))
        #expect(!installed("Qwen/Qwen3-8B-Base", [local("Qwen/Qwen3-8B", .huggingFaceCache)]))
    }

    @Test func matchesOllamaLibraryNamesIncludingQuantizedTags() {
        #expect(installed("Qwen/Qwen3-8B", [local("qwen3:8b", .ollama)]))
        #expect(installed("Qwen/Qwen3-8B", [local("qwen3:8b-q4_K_M", .ollama)]))
        #expect(!installed("Qwen/Qwen3-8B", [local("qwen3:latest", .ollama)]))
        #expect(!installed("Qwen/Qwen3-8B", [local("qwen3:14b", .ollama)]))
    }

    @Test func matchesHubPullsAsTheOllamaScannerListsThem() throws {
        let store = try ModelInventoryTestDirectory()

        try store.writeFile("blobs/sha256-w", bytes: 10)
        try store.writeFile(
            "manifests/hf.co/unsloth/Qwen3-8B-GGUF/Q4_K_M",
            contents: Data(
                """
                {"layers": [{"digest": "sha256:w", "mediaType": "application/vnd.ollama.image.model"}]}
                """.utf8))
        let scanned = OllamaModelScanner(root: store.url).scan()

        #expect(installed("unsloth/Qwen3-8B-GGUF", scanned))
        #expect(!installed("unsloth/Qwen3-14B-GGUF", scanned))
    }

    @Test func similarNamesAreNotInstalled() {
        #expect(!installed("Qwen/Qwen3-8B-Base", [local("Qwen3-8B", .custom)]))
        #expect(!installed("Qwen/Qwen3-8B-AWQ", [local("Qwen3-8B", .custom)]))
        #expect(!installed("org/model-embeddings", [local("model", .custom)]))
        #expect(!installed("meta/Llama-3-8B", []))
    }

    @Test func ggufRepositoriesPullIntoOllama() {
        #expect(
            HuggingFaceHubModelHandoff.downloadCommand(for: HuggingFaceHubModel(id: "org/Model-8B-GGUF"))
                == "ollama pull 'hf.co/org/Model-8B-GGUF'")
        #expect(
            HuggingFaceHubModelHandoff.downloadCommand(for: HuggingFaceHubModel(id: "org/Model-8B", libraryName: "gguf"))
                == "ollama pull 'hf.co/org/Model-8B'")
    }

    @Test func otherFormatsDownloadWithTheHuggingFaceCLI() {
        #expect(
            HuggingFaceHubModelHandoff.downloadCommand(for: HuggingFaceHubModel(id: "Qwen/Qwen3-8B", libraryName: "transformers"))
                == "hf download 'Qwen/Qwen3-8B'")
    }

    @Test func modelPageURL() {
        #expect(
            HuggingFaceHubModelHandoff.modelPageURL(for: HuggingFaceHubModel(id: "Qwen/Qwen3-8B"))?.absoluteString
                == "https://huggingface.co/Qwen/Qwen3-8B")
    }
}
