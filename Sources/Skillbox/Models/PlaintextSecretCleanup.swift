import Foundation

enum PlaintextSecretCleanupError: Error, LocalizedError, Equatable {
    case partiallyRemoved(removed: [String], reason: String)

    var errorDescription: String? {
        switch self {
        case .partiallyRemoved(let removed, let reason):
            "Removed \(removed.joined(separator: ", ")) before the cleanup failed: \(reason) The Keychain still holds the value."
        }
    }
}

/// Removes a secret's plaintext fallbacks only after every env copy matches the Keychain, so a mismatch removes nothing.
@MainActor
struct PlaintextSecretCleanup {
    let plaintextCopies: [EnvVar]
    let keychainHoldsSameValue: (EnvVar) async -> Bool
    let removeStaticHeader: (() async throws -> Void)?
    let removePlaintextCopy: (EnvVar) throws -> Void

    func run() async throws {
        for plaintextCopy in plaintextCopies {
            guard await keychainHoldsSameValue(plaintextCopy) else {
                throw KeychainSecretsModelError.keychainHoldsDifferentValue(plaintextCopy.key)
            }
        }
        var removed: [String] = []

        do {
            if let removeStaticHeader {
                try await removeStaticHeader()
                removed.append("the static header")
            }

            for plaintextCopy in plaintextCopies {
                try removePlaintextCopy(plaintextCopy)
                removed.append("\(plaintextCopy.key) from \(plaintextCopy.fileURL.lastPathComponent)")
            }
        } catch {
            guard !removed.isEmpty else { throw error }
            throw PlaintextSecretCleanupError.partiallyRemoved(removed: removed, reason: error.localizedDescription)
        }
    }
}
