import Foundation
import Observation

enum KeychainSecretsModelError: Error, LocalizedError, Equatable {
    case secretAlreadyExists(String)
    case keychainHoldsDifferentValue(String)
    case readBackMismatch(String)

    var errorDescription: String? {
        switch self {
        case .secretAlreadyExists(let name):
            "A Keychain secret named '\(name)' already exists."
        case .keychainHoldsDifferentValue(let name):
            "The Keychain already holds a different value for '\(name)'. Nothing was changed."
        case .readBackMismatch(let name):
            "The Keychain copy of '\(name)' did not match after writing, so it was removed. Nothing else was changed."
        }
    }
}

/// Env secrets kept in the login Keychain instead of settings.json, listed by name only.
@MainActor
@Observable
final class KeychainSecretsModel {
    private(set) var secretNames: [String] = []
    private(set) var lastError: String?

    private let secretStore: any KeychainSecretStoring

    init(secretStore: any KeychainSecretStoring = SystemKeychainSecretStore()) {
        self.secretStore = secretStore
    }

    func reload() {
        do {
            secretNames = try secretStore.secretNames()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Shows a failed Keychain action in the Env tab's error banner.
    func reportError(_ error: Error) {
        lastError = error.localizedDescription
    }

    func dismissError() {
        lastError = nil
    }

    func containsSecret(named name: String) -> Bool {
        secretNames.contains(name)
    }

    func filteredSecretNames(matching query: String) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return secretNames }
        return secretNames.filter { $0.localizedCaseInsensitiveContains(trimmed) }
    }

    /// Stores a new secret and verifies it by reading it back.
    func addSecret(named name: String, value: String) throws {
        try KeychainSecretValidation.validateName(name)
        try KeychainSecretValidation.validateValue(value)
        if try secretStore.secretNames().contains(name) {
            throw KeychainSecretsModelError.secretAlreadyExists(name)
        }
        try writeAndVerifyNewSecret(named: name, value: value)
        reload()
    }

    /// Reads a value only on explicit user action, such as reveal or copy.
    func readSecretValue(named name: String) throws -> String {
        try secretStore.readSecretValue(named: name)
    }

    func deleteSecret(named name: String) throws {
        try secretStore.deleteSecret(named: name)
        reload()
    }

    /// Copies a plaintext env secret into the Keychain and verifies it; the plaintext copy stays until the user removes it.
    func copyEnvSecretToKeychain(_ envVar: EnvVar) throws {
        try KeychainSecretValidation.validateName(envVar.key)
        try KeychainSecretValidation.validateValue(envVar.value)
        if try secretStore.secretNames().contains(envVar.key) {
            guard try secretStore.readSecretValue(named: envVar.key) == envVar.value else {
                throw KeychainSecretsModelError.keychainHoldsDifferentValue(envVar.key)
            }
            reload()
            return
        }
        try writeAndVerifyNewSecret(named: envVar.key, value: envVar.value)
        reload()
    }

    /// True when the Keychain holds this env var's exact value, so removing the plaintext copy loses nothing.
    func keychainHoldsSameValue(as envVar: EnvVar) -> Bool {
        guard containsSecret(named: envVar.key) else { return false }
        return (try? secretStore.readSecretValue(named: envVar.key)) == envVar.value
    }

    /// A read-back mismatch deletes the new item so a failed copy leaves no trace.
    private func writeAndVerifyNewSecret(named name: String, value: String) throws {
        try secretStore.writeSecretValue(value, named: name)
        let storedValue = try? secretStore.readSecretValue(named: name)
        guard storedValue == value else {
            try? secretStore.deleteSecret(named: name)
            throw KeychainSecretsModelError.readBackMismatch(name)
        }
    }
}
