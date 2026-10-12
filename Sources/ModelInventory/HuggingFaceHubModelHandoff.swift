import Foundation

/// Links a Hub search result to the local inventory and to the tools that download it.
public enum HuggingFaceHubModelHandoff {
    private static let minimumMatchLength = 3

    /// Best-effort installed check: a local model name and the Hub name contain one another.
    public static func isInstalled(_ model: HuggingFaceHubModel, localModelNames: [String]) -> Bool {
        let hubName = model.name.lowercased()
        guard hubName.count >= minimumMatchLength else { return false }
        return localModelNames.contains { localName in
            let lowered = localName.lowercased()
            guard lowered.count >= minimumMatchLength else { return false }
            return lowered.contains(hubName) || hubName.contains(lowered)
        }
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
