import Testing
@testable import ModelInventory

struct HuggingFaceHubModelHandoffTests {
    @Test func matchesLocalFileNamedAfterTheRepository() {
        #expect(HuggingFaceHubModelHandoff.isInstalled(
            HuggingFaceHubModel(id: "Qwen/Qwen3.5-9B"), localModelNames: ["Qwen_Qwen3.5-9B-Q4_K_M"]
        ))
    }

    @Test func notInstalledWithoutOverlap() {
        #expect(!HuggingFaceHubModelHandoff.isInstalled(HuggingFaceHubModel(id: "meta/Llama-3-70B"), localModelNames: ["Qwen3-8B"]))
        #expect(!HuggingFaceHubModelHandoff.isInstalled(HuggingFaceHubModel(id: "meta/Llama-3-8B"), localModelNames: []))
    }

    @Test func veryShortLocalNamesNeverMatch() {
        #expect(!HuggingFaceHubModelHandoff.isInstalled(HuggingFaceHubModel(id: "org/phi-4"), localModelNames: ["4", "ph"]))
    }

    @Test func ggufRepositoriesPullIntoOllama() {
        #expect(HuggingFaceHubModelHandoff.downloadCommand(for: HuggingFaceHubModel(id: "org/Model-8B-GGUF"))
            == "ollama pull hf.co/org/Model-8B-GGUF")
        #expect(HuggingFaceHubModelHandoff.downloadCommand(for: HuggingFaceHubModel(id: "org/Model-8B", libraryName: "gguf"))
            == "ollama pull hf.co/org/Model-8B")
    }

    @Test func otherFormatsDownloadWithTheHuggingFaceCLI() {
        #expect(HuggingFaceHubModelHandoff.downloadCommand(for: HuggingFaceHubModel(id: "Qwen/Qwen3-8B", libraryName: "transformers"))
            == "hf download Qwen/Qwen3-8B")
    }

    @Test func modelPageURL() {
        #expect(HuggingFaceHubModelHandoff.modelPageURL(for: HuggingFaceHubModel(id: "Qwen/Qwen3-8B"))?.absoluteString
            == "https://huggingface.co/Qwen/Qwen3-8B")
    }
}
