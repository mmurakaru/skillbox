import Foundation
import ModelInventory

/// UserDefaults keys behind the Local models settings, shared by the settings form and the launch-time scan.
enum LocalModelScanSettings {
    static let scanOllamaKey = "localModelsScanOllama"
    static let scanHuggingFaceKey = "localModelsScanHuggingFace"
    static let scanLMStudioKey = "localModelsScanLMStudio"
    static let scanOpenWhisprKey = "localModelsScanOpenWhispr"
    static let scanAppSupportKey = "localModelsScanAppSupport"
    static let customPathsKey = "localModelsCustomPaths"

    /// Reads the saved scan configuration; sources nobody has turned off default to on.
    static func configuration(from defaults: UserDefaults = .standard) -> LocalModelScanConfiguration {
        func isEnabled(_ key: String) -> Bool { defaults.object(forKey: key) as? Bool ?? true }
        return LocalModelScanConfiguration(
            ollama: isEnabled(scanOllamaKey),
            huggingFace: isEnabled(scanHuggingFaceKey),
            lmStudio: isEnabled(scanLMStudioKey),
            openWhispr: isEnabled(scanOpenWhisprKey),
            appSupport: isEnabled(scanAppSupportKey),
            customPaths: LocalModelScanConfiguration.parseCustomPaths(defaults.string(forKey: customPathsKey) ?? "")
        )
    }
}
