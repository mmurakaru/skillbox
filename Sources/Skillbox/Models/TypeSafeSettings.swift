import Foundation
import Observation

/// Shares the saved TypeSafe API key between Settings and automatic classification.
@MainActor
@Observable
final class TypeSafeSettings {
    private(set) var apiKey = ""
    private(set) var lastError: String?
    private let credentials = TypeSafeCredentials()

    init() {
        do { apiKey = try credentials.readAPIKey() }
        catch { lastError = error.localizedDescription }
    }

    func saveAPIKey(_ value: String) {
        do {
            let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
            try credentials.saveAPIKey(key)
            apiKey = key
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}
