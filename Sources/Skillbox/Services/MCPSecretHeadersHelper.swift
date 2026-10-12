import Foundation

enum MCPSecretHeadersHelperError: Error, LocalizedError, Equatable {
    case invalidHeaderName(String)
    case invalidValuePrefix(String)
    case helperOutputInvalid
    case helperNotInstalled(String)

    var errorDescription: String? {
        switch self {
        case .invalidHeaderName(let name):
            "Header name '\(name)' may only contain letters, digits, and hyphens."
        case .invalidValuePrefix(let prefix):
            "Header value prefix '\(prefix)' may only contain letters, digits, spaces, dots, underscores, and hyphens."
        case .helperOutputInvalid:
            "The headers helper did not print valid header JSON. Check that the Keychain secret exists and has no quotes or backslashes."
        case .helperNotInstalled(let server):
            "MCP server '\(server)' does not use the Skillbox headers helper after the update. The change was not applied as expected."
        }
    }
}

/// Builds and checks the `headersHelper` command that reads one Keychain secret into an MCP request header.
enum MCPSecretHeadersHelper {
    static let defaultHeaderName = "Authorization"
    static let defaultValuePrefix = "Bearer "

    static func validateHeaderName(_ headerName: String) throws {
        guard headerName.wholeMatch(of: /[A-Za-z0-9-]+/) != nil else {
            throw MCPSecretHeadersHelperError.invalidHeaderName(headerName)
        }
    }

    static func validateValuePrefix(_ valuePrefix: String) throws {
        guard valuePrefix.wholeMatch(of: /[A-Za-z0-9 ._-]*/) != nil else {
            throw MCPSecretHeadersHelperError.invalidValuePrefix(valuePrefix)
        }
    }

    static func command(secretName: String, headerName: String, valuePrefix: String) throws -> String {
        try KeychainSecretValidation.validateName(secretName)
        return try command(
            secretReadCommand: SystemKeychainSecretStore.readCommand(forSecretNamed: secretName),
            headerName: headerName,
            valuePrefix: valuePrefix
        )
    }

    /// Prints `{"<header>":"<prefix><secret>"}` or nothing with a non-zero exit; quotes and backslashes are refused, not escaped.
    static func command(secretReadCommand: String, headerName: String, valuePrefix: String) throws -> String {
        try validateHeaderName(headerName)
        try validateValuePrefix(valuePrefix)
        return "value=$(\(secretReadCommand) 2>/dev/null) && [ -n \"$value\" ] && case \"$value\" in *[\\\"\\\\]*) false ;; *) printf '{\"\(headerName)\":\"\(valuePrefix)%s\"}' \"$value\" ;; esac"
    }

    /// True when the command names this Keychain secret, so Skillbox can show which servers use it.
    static func commandReadsSecret(_ command: String, secretName: String) -> Bool {
        command.contains(SystemKeychainSecretStore.readCommand(forSecretNamed: secretName))
    }

    /// Runs the command in a shell like Claude Code does; the output is parsed, never shown or logged.
    static func verifyCommandPrintsHeader(_ command: String, headerName: String, processRunner: any ProcessRunning) throws {
        let result = try processRunner.run(executablePath: "/bin/sh", arguments: ["-c", command], standardInput: nil)
        guard result.exitCode == 0,
              let object = try? JSONSerialization.jsonObject(with: Data(result.standardOutput.utf8)) as? [String: String],
              let headerValue = object[headerName], !headerValue.isEmpty else {
            throw MCPSecretHeadersHelperError.helperOutputInvalid
        }
    }
}
