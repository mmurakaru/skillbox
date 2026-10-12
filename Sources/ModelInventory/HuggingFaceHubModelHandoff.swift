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
                if let namespacedRepositoryID = ollamaNamespacedRepositoryID(local.name) {
                    return namespacedRepositoryID == repositoryID
                }

                return ollamaIdentity(local.name) == baseName
            default:
                let fileIdentity = normalizedIdentity(strippingQuantization(from: local.name))

                return fileIdentity == baseName || fileIdentity == labQualifiedName
            }
        }
    }

    /// The scanner drops the registry, so `ollama pull hf.co/<org>/<repo>:<quant>` lists as `<org>/<repo>:<quant>`.
    private static func ollamaNamespacedRepositoryID(_ ollamaName: String) -> String? {
        let repository = ollamaName.lowercased().split(separator: ":", maxSplits: 1).first.map(String.init) ?? ""

        return repository.contains("/") ? repository : nil
    }

    /// `qwen3:8b-q4_K_M` names the Hub repository `Qwen3-8B`; quantization and the default `latest` tag add nothing.
    private static func ollamaIdentity(_ ollamaName: String) -> String {
        let parts = ollamaName.split(separator: ":", maxSplits: 1).map(String.init)
        let tag = parts.count == 2 ? strippingQuantization(from: parts[1]) : ""

        guard !tag.isEmpty, tag.lowercased() != "latest" else { return normalizedIdentity(parts[0]) }

        return normalizedIdentity(parts[0] + "-" + tag)
    }

    /// Drops quantization suffixes such as `-Q4_K_M`, `.Q8_0`, or `-f16` that local GGUF file names add.
    private static func strippingQuantization(from fileName: String) -> String {
        fileName.replacing(/(?i)(?:^|[-_.])(?:i?q\d\w*|bf16|fp?16|f32)$/, with: "")
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
        isGGUFRepository(model) ? "ollama pull 'hf.co/\(model.id)'" : "hf download '\(model.id)'"
    }

    public static func modelPageURL(for model: HuggingFaceHubModel) -> URL? {
        URL(string: "https://huggingface.co/\(model.id)")
    }

    private static func isGGUFRepository(_ model: HuggingFaceHubModel) -> Bool {
        model.libraryName?.lowercased() == "gguf" || model.id.lowercased().contains("gguf")
    }
}
