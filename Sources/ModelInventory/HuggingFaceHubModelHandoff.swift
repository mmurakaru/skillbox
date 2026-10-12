import Foundation

/// Links a Hub search result to the local inventory and to the tools that download it.
public enum HuggingFaceHubModelHandoff {
    /// True when a local model is this exact Hub repository, not merely a name that contains it.
    public static func isInstalled(_ model: HuggingFaceHubModel, localModels: [LocalModel]) -> Bool {
        let repositoryID = model.id.lowercased()
        let baseName = normalizedIdentity(strippingSuffix("-gguf", from: model.name))
        let labQualifiedName = normalizedIdentity(model.lab + "-" + strippingSuffix("-gguf", from: model.name))
        return localModels.contains { local in
            switch local.source {
            case .huggingFaceCache:
                return local.name.lowercased() == repositoryID
            case .ollama:
                if let pulledRepositoryID = ollamaPulledRepositoryID(local.name) {
                    return pulledRepositoryID == repositoryID
                }
                return ollamaIdentity(local.name) == baseName
            default:
                let fileIdentity = normalizedIdentity(strippingQuantization(from: local.name))
                return fileIdentity == baseName || fileIdentity == labQualifiedName
            }
        }
    }

    /// `hf.co/<org>/<repo>:<quant>` names come from pulling a Hub repository into Ollama.
    private static func ollamaPulledRepositoryID(_ ollamaName: String) -> String? {
        let lowered = ollamaName.lowercased()
        guard lowered.hasPrefix("hf.co/") else { return nil }
        let repository = lowered.dropFirst("hf.co/".count)
        return String(repository.split(separator: ":", maxSplits: 1).first ?? repository)
    }

    /// `qwen3:8b` names the Hub repository `Qwen3-8B`; the default `latest` tag adds nothing.
    private static func ollamaIdentity(_ ollamaName: String) -> String {
        let parts = ollamaName.split(separator: ":", maxSplits: 1).map(String.init)
        let modelName = parts[0].split(separator: "/").last.map(String.init) ?? parts[0]
        guard parts.count == 2, parts[1].lowercased() != "latest" else { return normalizedIdentity(modelName) }
        return normalizedIdentity(modelName + "-" + parts[1])
    }

    /// Drops quantization suffixes such as `-Q4_K_M`, `.Q8_0`, or `-f16` that local GGUF file names add.
    private static func strippingQuantization(from fileName: String) -> String {
        fileName.replacing(/(?i)[-_.](?:i?q\d\w*|bf16|fp?16|f32)$/, with: "")
    }

    private static func strippingSuffix(_ suffix: String, from name: String) -> String {
        name.lowercased().hasSuffix(suffix) ? String(name.dropLast(suffix.count)) : name
    }

    /// Case and separators vary between tools (`Qwen3.5-9B`, `qwen3_5-9b`), so compare a normalized form.
    private static func normalizedIdentity(_ name: String) -> String {
        name.lowercased().map { "_.: ".contains($0) ? "-" : $0 }.reduce(into: "") { $0.append($1) }
    }

    /// GGUF repos pull straight into Ollama; other formats download with the Hugging Face CLI.
    public static func downloadCommand(for model: HuggingFaceHubModel) -> String {
        isGGUFRepository(model) ? "ollama pull hf.co/\(model.id)" : "hf download \(model.id)"
    }

    public static func modelPageURL(for model: HuggingFaceHubModel) -> URL? {
        URL(string: "https://huggingface.co/\(model.id)")
    }

    private static func isGGUFRepository(_ model: HuggingFaceHubModel) -> Bool {
        model.libraryName?.lowercased() == "gguf" || model.id.lowercased().contains("gguf")
    }
}
