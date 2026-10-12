import Foundation

/// Removes a secret's plaintext fallbacks only after every env copy matches the Keychain, so a mismatch removes nothing.
struct PlaintextSecretCleanup {
    let plaintextCopies: [EnvVar]
    let keychainHoldsSameValue: (EnvVar) -> Bool
    let removeStaticHeader: (() throws -> Void)?
    let removePlaintextCopy: (EnvVar) throws -> Void

    func run() throws {
        if let mismatchedCopy = plaintextCopies.first(where: { !keychainHoldsSameValue($0) }) {
            throw KeychainSecretsModelError.keychainHoldsDifferentValue(mismatchedCopy.key)
        }

        try removeStaticHeader?()
        for plaintextCopy in plaintextCopies {
            try removePlaintextCopy(plaintextCopy)
        }
    }
}
