import Testing
import Foundation
@testable import ModelInventory

struct ModelRuntimeDecisionTests {
    private func model(_ name: String, source: LocalModelSource, format: LocalModelFormat = .gguf) -> LocalModel {
        LocalModel(id: name, name: name, source: source, path: URL(fileURLWithPath: "/models/\(name)"),
                   format: format, sizeBytes: 1)
    }

    @Test func loadedOllamaModelIsStoppableThroughOllama() {
        let state = ModelRuntimeDecision.evaluate(
            model: model("llama3:8b", source: .ollama, format: .ollamaBlob),
            loadedOllamaModelName: "llama3:8b", fileHolder: nil
        )
        #expect(state == ModelRuntimeState(stopTarget: .ollama(modelName: "llama3:8b"), hostName: "Ollama"))
    }

    @Test func unloadedOllamaModelIsIdle() {
        let state = ModelRuntimeDecision.evaluate(
            model: model("llama3:8b", source: .ollama, format: .ollamaBlob),
            loadedOllamaModelName: nil, fileHolder: nil
        )
        #expect(state == nil)
    }

    @Test func dedicatedServerProcessIsStoppable() {
        let state = ModelRuntimeDecision.evaluate(
            model: model("gpt-oss-20b", source: .custom),
            loadedOllamaModelName: nil, fileHolder: ModelFileHolder(pid: 4242, commandName: "llama-server")
        )
        #expect(state?.stopTarget == .process(pid: 4242, commandName: "llama-server"))
    }

    @Test func modelHeldByAnotherAppIsLoadedButNotStoppable() {
        let state = ModelRuntimeDecision.evaluate(
            model: model("whisper", source: .openWhispr),
            loadedOllamaModelName: nil, fileHolder: ModelFileHolder(pid: 99, commandName: "OpenWhispr")
        )
        #expect(state == ModelRuntimeState(stopTarget: nil, hostName: "OpenWhispr"))
    }

    @Test func modelWithoutHolderIsIdle() {
        let state = ModelRuntimeDecision.evaluate(
            model: model("whisper", source: .openWhispr), loadedOllamaModelName: nil, fileHolder: nil
        )
        #expect(state == nil)
    }

    @Test func ollamaNameMatchesWithOrWithoutRegistryPrefix() {
        let library = model("llama3:8b", source: .ollama, format: .ollamaBlob)
        let namespaced = model("user/mymodel:q4", source: .ollama, format: .ollamaBlob)
        let loaded = ["llama3:8b", "hf.co/user/mymodel:q4"]

        #expect(ModelRuntimeDecision.loadedOllamaName(for: library, among: loaded) == "llama3:8b")
        #expect(ModelRuntimeDecision.loadedOllamaName(for: namespaced, among: loaded) == "hf.co/user/mymodel:q4")
        #expect(ModelRuntimeDecision.loadedOllamaName(for: model("ama3:8b", source: .ollama), among: loaded) == nil)
    }

    @Test func parsesOllamaRunningModels() {
        let data = Data(#"{"models":[{"name":"llama3:8b","size":1},{"name":"qwen3:4b"}]}"#.utf8)
        #expect(OllamaRunningModels.names(fromPSResponse: data) == ["llama3:8b", "qwen3:4b"])
        #expect(OllamaRunningModels.names(fromPSResponse: Data("not json".utf8)).isEmpty)
    }

    @Test func parsesFirstHolderPerPathFromLsofFields() {
        let output = """
        p405
        cllama-server
        ftxt
        n/models/a.gguf
        p621
        cOtherApp
        f12
        n/models/a.gguf
        f13
        n/models/b.gguf
        """
        let holders = LsofFileHolders.parse(fieldOutput: output)
        #expect(holders["/models/a.gguf"] == ModelFileHolder(pid: 405, commandName: "llama-server"))
        #expect(holders["/models/b.gguf"] == ModelFileHolder(pid: 621, commandName: "OtherApp"))
    }

    @Test func onlyContentAddressedOllamaModelsStayOutOfTheTrash() {
        #expect(LocalModelTrashPolicy.canMoveToTrash(model("a", source: .custom, format: .gguf)))
        #expect(LocalModelTrashPolicy.canMoveToTrash(model("b", source: .huggingFaceCache, format: .safetensors)))
        #expect(!LocalModelTrashPolicy.canMoveToTrash(model("c", source: .ollama, format: .ollamaBlob)))
    }

    @Test func aWorkingDirectoryIsNotALoadedModel() {
        let output = """
        p100
        czsh
        fcwd
        n/models/folder
        p200
        cllama-server
        f7
        n/models/folder
        """
        #expect(LsofFileHolders.parse(fieldOutput: output)["/models/folder"] == ModelFileHolder(pid: 200, commandName: "llama-server"))
    }

    @Test func canonicalPathsFollowSymlinksTheWayLsofReportsThem() throws {
        let directory = try ModelInventoryTestDirectory()
        let file = try directory.writeFile("real/model.gguf", bytes: 8)
        let link = directory.url.appending(path: "linked")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: directory.url.appending(path: "real"))

        let canonical = CanonicalFilePath.of(link.appending(path: "model.gguf"))

        #expect(canonical == CanonicalFilePath.of(file))
        #expect(!canonical.contains("/linked/"))
        #expect(canonical.hasPrefix("/private/") || !file.path.hasPrefix("/var/"))
    }
}
