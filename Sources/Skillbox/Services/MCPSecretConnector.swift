import Foundation

enum MCPSecretConnectorError: Error, LocalizedError, Equatable {
    case rollbackFailed(String)

    var errorDescription: String? {
        switch self {
        case .rollbackFailed(let server):
            "The final check failed and the previous headers helper of '\(server)' could not be restored. Check that server in the Claude Code config."
        }
    }
}

/// Connects a Keychain secret to a user-scope Claude Code HTTP MCP server through `headersHelper`.
struct MCPSecretConnector: Sendable {
    var configEditor = ClaudeGlobalConfigEditor(configURL: ClaudeGlobalConfigEditor.defaultConfigURL())
    var processRunner: any ProcessRunning = SystemProcessRunner()

    /// Restores the previous helper if the final check fails; static headers stay as Claude Code's fallback.
    func connect(secretName: String, serverName: String, headerName: String, valuePrefix: String) throws {
        let command = try MCPSecretHeadersHelper.command(secretName: secretName, headerName: headerName, valuePrefix: valuePrefix)
        try MCPSecretHeadersHelper.verifyCommandPrintsHeader(command, headerName: headerName, processRunner: processRunner)
        let previousHelper = try configEditor.userScopeHTTPServers().first(where: { $0.name == serverName })?.headersHelper
        try configEditor.updateUserScopeHTTPServer(named: serverName) { server in
            server["headersHelper"] = command
        }
        do {
            guard let installed = try configEditor.userScopeHTTPServers().first(where: { $0.name == serverName })?.headersHelper,
                  installed == command else {
                throw MCPSecretHeadersHelperError.helperNotInstalled(serverName)
            }
            try MCPSecretHeadersHelper.verifyCommandPrintsHeader(installed, headerName: headerName, processRunner: processRunner)
        } catch {
            do {
                try configEditor.updateUserScopeHTTPServer(named: serverName) { server in
                    server["headersHelper"] = previousHelper
                }
            } catch {
                throw MCPSecretConnectorError.rollbackFailed(serverName)
            }
            throw error
        }
    }

    /// Removes one static header so the server relies on its helper alone; drops an empty `headers` map.
    func removeStaticHeader(named headerName: String, fromServer serverName: String) throws {
        try configEditor.updateUserScopeHTTPServer(named: serverName) { server in
            var headers = server["headers"] as? [String: Any] ?? [:]
            headers.removeValue(forKey: headerName)
            if headers.isEmpty {
                server.removeValue(forKey: "headers")
            } else {
                server["headers"] = headers
            }
        }
    }
}
