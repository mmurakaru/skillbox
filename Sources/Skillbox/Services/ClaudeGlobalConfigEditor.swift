import Foundation

// swiftlint:disable no_untyped_dictionaries - JSON trust boundary: edits the Claude Code global config, which must round-trip keys it does not model.

enum ClaudeGlobalConfigError: Error, LocalizedError, Equatable {
    case configLocked
    case configUnreadable
    case serverNotFound(String)
    case serverIsNotHTTP(String)

    var errorDescription: String? {
        switch self {
        case .configLocked:
            "Claude Code config is locked by another writer. Try again in a moment."
        case .configUnreadable:
            "Claude Code config could not be read as JSON. Nothing was changed."
        case .serverNotFound(let name):
            "MCP server '\(name)' was not found in the user-scope Claude Code config."
        case .serverIsNotHTTP(let name):
            "MCP server '\(name)' is not an HTTP server, so it has no request headers."
        }
    }
}

/// A user-scope HTTP MCP server from the Claude Code global config, with only the fields Skillbox shows.
struct ClaudeHTTPMCPServer: Identifiable, Equatable {
    let name: String
    let url: String
    let staticHeaderNames: [String]
    let headersHelper: String?

    var id: String { name }
}

/// Edits the Claude Code global config (`~/.claude.json`) under the same lock the Claude Code CLI takes.
struct ClaudeGlobalConfigEditor: Sendable {
    let configURL: URL
    /// A lock directory older than this is abandoned; matches the lock library Claude Code uses.
    var staleLockAge: TimeInterval = 10
    var lockWaitLimit: TimeInterval = 3

    /// `$CLAUDE_CONFIG_DIR/.claude.json` when that variable is set, otherwise `~/.claude.json`.
    static func defaultConfigURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let configDirectory = environment["CLAUDE_CONFIG_DIR"], !configDirectory.isEmpty {
            return URL(fileURLWithPath: (configDirectory as NSString).expandingTildeInPath).appendingPathComponent(".claude.json")
        }

        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json")
    }

    /// Writes go to the symlink target so a linked config stays linked.
    var resolvedConfigURL: URL { configURL.resolvingSymlinksInPath() }

    /// The CLI's lock library locks the real path, so a symlinked config shares the same lock.
    var lockDirectoryURL: URL {
        resolvedConfigURL.deletingLastPathComponent().appendingPathComponent(resolvedConfigURL.lastPathComponent + ".lock")
    }

    func userScopeHTTPServers() throws -> [ClaudeHTTPMCPServer] {
        let root = try readConfigRoot()
        let servers = root["mcpServers"] as? [String: Any] ?? [:]

        return servers.compactMap { name, value in
            guard let server = value as? [String: Any], server["type"] as? String == "http" else { return nil }

            return ClaudeHTTPMCPServer(
                name: name,
                url: server["url"] as? String ?? "",
                staticHeaderNames: (server["headers"] as? [String: Any] ?? [:]).keys.sorted(),
                headersHelper: server["headersHelper"] as? String
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Changes only the named user-scope HTTP server's text; every other byte of the file stays as written.
    func updateUserScopeHTTPServer(named serverName: String, _ mutate: (inout [String: Any]) -> Void) throws {
        try withConfigLock {
            let text = try readConfigText()
            let root = try parseConfigRoot(text)
            let servers = root["mcpServers"] as? [String: Any] ?? [:]

            guard var server = servers[serverName] as? [String: Any] else {
                throw ClaudeGlobalConfigError.serverNotFound(serverName)
            }
            guard server["type"] as? String == "http" else { throw ClaudeGlobalConfigError.serverIsNotHTTP(serverName) }
            mutate(&server)
            let updatedText = try JSONMemberTextEditor.replacingMember(at: ["mcpServers", serverName], in: text, with: server)

            guard (try? parseConfigRoot(updatedText)) != nil else { throw ClaudeGlobalConfigError.configUnreadable }
            try replaceConfigAtomically(with: Data(updatedText.utf8))
        }
    }

    private func readConfigRoot() throws -> [String: Any] {
        try parseConfigRoot(try readConfigText())
    }

    private func readConfigText() throws -> String {
        guard let data = try? Data(contentsOf: resolvedConfigURL), let text = String(data: data, encoding: .utf8) else {
            throw ClaudeGlobalConfigError.configUnreadable
        }

        return text
    }

    private func parseConfigRoot(_ text: String) throws -> [String: Any] {
        guard let root = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
            throw ClaudeGlobalConfigError.configUnreadable
        }

        return root
    }

    /// Writes a sibling temp file with the original permissions, then renames it over the config.
    private func replaceConfigAtomically(with data: Data) throws {
        let fileManager = FileManager.default
        let targetURL = resolvedConfigURL
        let permissions = (try fileManager.attributesOfItem(atPath: targetURL.path)[.posixPermissions] as? NSNumber) ?? 0o600
        let temporaryURL = targetURL.deletingLastPathComponent()
            .appendingPathComponent(".\(targetURL.lastPathComponent).skillbox-\(UUID().uuidString).tmp")

        guard fileManager.createFile(atPath: temporaryURL.path, contents: data, attributes: [.posixPermissions: permissions]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        guard rename(temporaryURL.path, targetURL.path) == 0 else {
            let renameError = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)

            try? fileManager.removeItem(at: temporaryURL)
            throw renameError
        }
    }

    /// `mkdir` is atomic, so the lock directory works across processes the same way the CLI's lock does.
    private func withConfigLock<Result>(_ body: () throws -> Result) throws -> Result {
        let deadline = Date().addingTimeInterval(lockWaitLimit)

        while mkdir(lockDirectoryURL.path, 0o755) != 0 {
            guard errno == EEXIST else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }

            if isLockStale() {
                rmdir(lockDirectoryURL.path)
                continue
            }

            guard Date() < deadline else { throw ClaudeGlobalConfigError.configLocked }
            Thread.sleep(forTimeInterval: 0.05)
        }
        defer { rmdir(lockDirectoryURL.path) }

        return try body()
    }

    private func isLockStale() -> Bool {
        guard let modified = try? FileManager.default.attributesOfItem(atPath: lockDirectoryURL.path)[.modificationDate] as? Date else {
            return false
        }

        return Date().timeIntervalSince(modified) > staleLockAge
    }
}
