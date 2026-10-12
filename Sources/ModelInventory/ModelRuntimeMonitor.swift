import Foundation
import Darwin

/// Reads which local models are loaded in memory and unloads the ones that can be stopped cleanly.
public protocol ModelRuntimeMonitoring: Sendable {
    func runtimeStates(for models: [LocalModel]) async -> [String: ModelRuntimeState]
    func stop(_ target: ModelStopTarget, weightFileURLs: [URL]) async
}

/// Uses Ollama's local HTTP API and one `lsof` call per refresh for weight files held open by other processes.
public struct ModelRuntimeMonitor: ModelRuntimeMonitoring {
    private let ollamaBaseURL: URL
    private let session: URLSession

    public init(ollamaBaseURL: URL = URL(string: "http://localhost:11434")!, session: URLSession = .shared) {
        self.ollamaBaseURL = ollamaBaseURL
        self.session = session
    }

    public func runtimeStates(for models: [LocalModel]) async -> [String: ModelRuntimeState] {
        let hasOllamaModels = models.contains { $0.source == .ollama }
        let loadedOllamaNames = hasOllamaModels ? await loadedOllamaModelNames() : []
        let weightFilePathsByModelID = Dictionary(uniqueKeysWithValues: models
            .filter { $0.source != .ollama && Self.isWeightFile($0) }
            .map { ($0.id, $0.weightFileURLs.map(CanonicalFilePath.of)) })
        let holders = await Self.fileHolders(forPaths: Array(Set(weightFilePathsByModelID.values.joined())).sorted())

        var states: [String: ModelRuntimeState] = [:]
        for model in models {
            let state = ModelRuntimeDecision.evaluate(
                model: model,
                loadedOllamaModelName: ModelRuntimeDecision.loadedOllamaName(for: model, among: loadedOllamaNames),
                fileHolder: weightFilePathsByModelID[model.id]?.lazy.compactMap { holders[$0] }.first
            )
            if let state { states[model.id] = state }
        }
        return states
    }

    public func stop(_ target: ModelStopTarget, weightFileURLs: [URL]) async {
        switch target {
        case .ollama(let modelName):
            await unloadOllamaModel(named: modelName)
        case .process(let pid, let commandName):
            // The pid may have been reused since the last refresh, so confirm it still holds one of these files.
            let paths = weightFileURLs.map(CanonicalFilePath.of)
            let holders = await Self.fileHolders(forPaths: paths)
            guard paths.contains(where: { holders[$0] == ModelFileHolder(pid: pid, commandName: commandName) }) else { return }
            kill(pid, SIGTERM)
        }
    }

    private static func isWeightFile(_ model: LocalModel) -> Bool {
        model.format == .gguf || model.format == .safetensors
    }

    private func loadedOllamaModelNames() async -> [String] {
        var request = URLRequest(url: ollamaBaseURL.appending(path: "api/ps"))
        request.timeoutInterval = 2
        guard let (data, _) = try? await session.data(for: request) else { return [] }
        return OllamaRunningModels.names(fromPSResponse: data)
    }

    /// Ollama unloads a model when a request sets `keep_alive` to 0.
    private func unloadOllamaModel(named modelName: String) async {
        var request = URLRequest(url: ollamaBaseURL.appending(path: "api/generate"))
        request.httpMethod = "POST"
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["model": modelName, "keep_alive": 0])
        _ = try? await session.data(for: request)
    }

    private static func fileHolders(forPaths paths: [String]) async -> [String: ModelFileHolder] {
        guard !paths.isEmpty else { return [:] }
        // Waiting on lsof blocks its thread, so keep it off the Swift concurrency pool.
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let output = runTool("/usr/sbin/lsof", ["-F", "pcfn", "--"] + paths)
                continuation.resume(returning: output.map(LsofFileHolders.parse(fieldOutput:)) ?? [:])
            }
        }
    }

    private static func runTool(_ executablePath: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}

/// Parses Ollama's `/api/ps` response into running model names.
public enum OllamaRunningModels {
    private struct PSResponse: Decodable {
        struct RunningModel: Decodable { let name: String }
        let models: [RunningModel]
    }

    public static func names(fromPSResponse data: Data) -> [String] {
        (try? JSONDecoder().decode(PSResponse.self, from: data))?.models.map(\.name) ?? []
    }
}

/// `lsof` reports canonical paths (for example `/private/tmp`), so lookups must use the same form.
public enum CanonicalFilePath {
    public static func of(_ url: URL) -> String {
        guard let resolved = realpath(url.path, nil) else { return url.path }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}

/// Parses `lsof -F pcfn` output into the first process holding each file path.
public enum LsofFileHolders {
    /// A working or root directory is not a loaded model, even when it is a model folder.
    private static let directoryDescriptors: Set<String> = ["cwd", "rtd"]

    public static func parse(fieldOutput: String) -> [String: ModelFileHolder] {
        var holders: [String: ModelFileHolder] = [:]
        var currentPID: Int32?
        var currentCommandName = ""
        var currentDescriptor = ""
        for line in fieldOutput.split(separator: "\n") {
            guard let field = line.first else { continue }
            let value = String(line.dropFirst())
            switch field {
            case "p":
                currentPID = Int32(value)
                currentCommandName = ""
            case "c":
                currentCommandName = value
            case "f":
                currentDescriptor = value
            case "n":
                if let currentPID, holders[value] == nil, !directoryDescriptors.contains(currentDescriptor) {
                    holders[value] = ModelFileHolder(pid: currentPID, commandName: currentCommandName)
                }
            default:
                break
            }
        }
        return holders
    }
}
