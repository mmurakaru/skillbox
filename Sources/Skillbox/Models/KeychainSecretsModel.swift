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

    func reload() async {
        do {
            secretNames = try await offMainActor { try $0.secretNames() }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func reportError(_ error: Error) {
        lastError = error.localizedDescription
    }

    func dismissError() {
        lastError = nil
    }

    func containsSecret(named name: String) -> Bool {
        secretNames.contains(name)
    }

    /// Keychain secrets show under "All scopes" and the Keychain filter, never under a settings scope.
    func visibleSecretNames(scopeKey: String?, searchQuery: String) -> [String] {
        let key = scopeKey ?? ""

        guard key.isEmpty || key == EnvVarStore.keychainScopeKey else { return [] }
        let trimmed = searchQuery.trimmingCharacters(in: .whitespaces)

        guard !trimmed.isEmpty else { return secretNames }

        return secretNames.filter { $0.localizedCaseInsensitiveContains(trimmed) }
    }

    /// Stores a new secret and verifies it by reading it back.
    func addSecret(named name: String, value: String) async throws {
        try KeychainSecretValidation.validateName(name)
        try KeychainSecretValidation.validateValue(value)

        if try await offMainActor({ try $0.secretNames() }).contains(name) {
            throw KeychainSecretsModelError.secretAlreadyExists(name)
        }

        try await writeAndVerifyNewSecret(named: name, value: value)
        await reload()
    }

    /// Reads a value only on explicit user action, such as reveal or copy.
    func readSecretValue(named name: String) async throws -> String {
        try await offMainActor { try $0.readSecretValue(named: name) }
    }

    func deleteSecret(named name: String) async throws {
        try await offMainActor { try $0.deleteSecret(named: name) }
        await reload()
    }

    /// Copies a plaintext env secret into the Keychain and verifies it; the plaintext copy stays until the user removes it.
    func copyEnvSecretToKeychain(_ envVar: EnvVar) async throws {
        try KeychainSecretValidation.validateName(envVar.key)
        try KeychainSecretValidation.validateValue(envVar.value)

        if try await offMainActor({ try $0.secretNames() }).contains(envVar.key) {
            guard try await readSecretValue(named: envVar.key) == envVar.value else {
                throw KeychainSecretsModelError.keychainHoldsDifferentValue(envVar.key)
            }
            await reload()

            return
        }

        try await writeAndVerifyNewSecret(named: envVar.key, value: envVar.value)
        await reload()
    }

    /// True when the Keychain holds this env var's exact value, so removing the plaintext copy loses nothing.
    func keychainHoldsSameValue(as envVar: EnvVar) async -> Bool {
        guard containsSecret(named: envVar.key) else { return false }

        return (try? await readSecretValue(named: envVar.key)) == envVar.value
    }

    /// A read-back mismatch deletes the new item so a failed copy leaves no trace.
    private func writeAndVerifyNewSecret(named name: String, value: String) async throws {
        let matches = try await offMainActor { store in
            try store.writeSecretValue(value, named: name)
            guard (try? store.readSecretValue(named: name)) == value else {
                try? store.deleteSecret(named: name)

                return false
            }

            return true
        }

        guard matches else { throw KeychainSecretsModelError.readBackMismatch(name) }
    }

    /// `security` can wait on a locked Keychain, so it never runs on the main actor that drives the menu bar panel.
    private func offMainActor<Value: Sendable>(
        _ work: @escaping @Sendable (any KeychainSecretStoring) throws -> Value
    ) async throws -> Value {
        let store = secretStore

        return try await Task.detached { try work(store) }.value
    }
}
