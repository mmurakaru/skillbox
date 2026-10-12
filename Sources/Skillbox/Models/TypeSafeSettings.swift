import Foundation
import Observation

/// Shares the saved TypeSafe API key between Settings and automatic classification.
@MainActor
@Observable
final class TypeSafeSettings {
    private(set) var apiKey = ""
    private(set) var lastError: String?
    private let credentials = TypeSafeCredentials()
    private let readKey: (Bool) throws -> String
    private(set) var needsUnlock = false

    init(readKey: ((Bool) throws -> String)? = nil) {
        let credentials = TypeSafeCredentials()

        self.readKey = readKey ?? { try credentials.readAPIKey(allowPrompt: $0) }
        loadSavedAPIKey(allowPrompt: false)
    }

    /// Password dialogs are permitted only after the user clicks Unlock saved key in Settings.
    func unlockSavedAPIKey() {
        loadSavedAPIKey(allowPrompt: true)
    }

    private func loadSavedAPIKey(allowPrompt: Bool) {
        do {
            apiKey = try readKey(allowPrompt)
            lastError = nil
            needsUnlock = false
        } catch {
            needsUnlock = true
            lastError =
                allowPrompt
                ? error.localizedDescription
                : "Saved TypeSafe key needs permission. Unlock it in Settings to resume automatic classification."
        }
    }

    func saveAPIKey(_ value: String) {
        do {
            let key = value.trimmingCharacters(in: .whitespacesAndNewlines)

            try credentials.saveAPIKey(key)
            apiKey = key
            needsUnlock = false
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}
