import Foundation

/// How a loaded model can be unloaded without quitting the app that hosts it.
public enum ModelStopTarget: Sendable, Equatable {
    case ollama(modelName: String)
    case process(pid: Int32, commandName: String)
}

/// A process that holds a model file open, which means the model is loaded in memory.
public struct ModelFileHolder: Sendable, Equatable {
    public let pid: Int32
    public let commandName: String

    public init(pid: Int32, commandName: String) {
        self.pid = pid
        self.commandName = commandName
    }
}

/// Runtime state of a loaded ("warm") model; `stopTarget` is nil when only quitting its host app would unload it.
public struct ModelRuntimeState: Sendable, Equatable {
    public let stopTarget: ModelStopTarget?
    public let hostName: String

    public init(stopTarget: ModelStopTarget?, hostName: String) {
        self.stopTarget = stopTarget
        self.hostName = hostName
    }
}

/// Decides whether a model is loaded and how it can be stopped.
public enum ModelRuntimeDecision {
    /// Process names that serve exactly one model and can be terminated on their own.
    public static let stoppableServerCommandNames: Set<String> = ["llama-server"]

    public static func evaluate(
        model: LocalModel,
        loadedOllamaModelName: String?,
        fileHolder: ModelFileHolder?
    ) -> ModelRuntimeState? {
        if model.source == .ollama {
            guard let loadedOllamaModelName else { return nil }

            return ModelRuntimeState(stopTarget: .ollama(modelName: loadedOllamaModelName), hostName: "Ollama")
        }

        guard let fileHolder else { return nil }
        let stoppable = stoppableServerCommandNames.contains(fileHolder.commandName)

        return ModelRuntimeState(
            stopTarget: stoppable ? .process(pid: fileHolder.pid, commandName: fileHolder.commandName) : nil,
            hostName: fileHolder.commandName
        )
    }

    /// Matches a scanned Ollama model to a running-model name; the API may prefix a registry host.
    public static func loadedOllamaName(for model: LocalModel, among loadedNames: [String]) -> String? {
        loadedNames.first { $0 == model.name || $0.hasSuffix("/" + model.name) }
    }
}
