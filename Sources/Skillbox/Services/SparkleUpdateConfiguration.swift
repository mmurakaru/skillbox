import Foundation

/// Source builds leave the signing key unset until binary updates are configured.
enum SparkleUpdateConfiguration {
    static func hasValidSigningKey(_ publicKey: String?) -> Bool {
        guard let publicKey, let key = Data(base64Encoded: publicKey) else { return false }

        return key.count == 32
    }
}
