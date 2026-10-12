import Foundation
import Testing

@testable import Skillbox

struct MCPSecretHeadersHelperTests {
    /// Runs the helper in a real shell with a stand-in read command, never the Keychain.
    private func runHelper(readCommand: String, headerName: String = "Authorization", valuePrefix: String = "Bearer ") throws
        -> ProcessRunResult
    {
        let command = try MCPSecretHeadersHelper.command(secretReadCommand: readCommand, headerName: headerName, valuePrefix: valuePrefix)

        return try SystemProcessRunner().run(executablePath: "/bin/sh", arguments: ["-c", command], standardInput: nil)
    }

    @Test func command_printsHeaderJSON() throws {
        let result = try runHelper(readCommand: "printf 'example-token%%value'")

        #expect(result.exitCode == 0)
        let object = try JSONSerialization.jsonObject(with: Data(result.standardOutput.utf8)) as? [String: String]

        #expect(object == ["Authorization": "Bearer example-token%value"])
    }

    @Test(arguments: ["false", "printf ''", #"printf 'has"quote'"#, #"printf 'has\\backslash'"#])
    func command_unsafeOrFailedRead_exitsNonZeroWithoutOutput(readCommand: String) throws {
        let result = try runHelper(readCommand: readCommand)

        #expect(result.exitCode != 0)
        #expect(result.standardOutput.isEmpty)
    }

    @Test func command_customHeaderWithoutPrefix() throws {
        let result = try runHelper(readCommand: "printf 'abc'", headerName: "X-Api-Key", valuePrefix: "")

        #expect(result.standardOutput == #"{"X-Api-Key":"abc"}"#)
    }

    @Test func command_rejectsUnsafeHeaderNameAndPrefix() {
        #expect(throws: MCPSecretHeadersHelperError.self) {
            try MCPSecretHeadersHelper.command(secretReadCommand: "true", headerName: "Bad\"Header", valuePrefix: "")
        }
        #expect(throws: MCPSecretHeadersHelperError.self) {
            try MCPSecretHeadersHelper.command(secretReadCommand: "true", headerName: "Authorization", valuePrefix: "%s'")
        }
    }

    @Test func command_forKeychainSecret_readsWithSystemSecurityTool() throws {
        let command = try MCPSecretHeadersHelper.command(
            secretName: "EXAMPLE_API_TOKEN", headerName: "Authorization", valuePrefix: "Bearer ")

        #expect(MCPSecretHeadersHelper.commandReadsSecret(command, secretName: "EXAMPLE_API_TOKEN"))
        #expect(!MCPSecretHeadersHelper.commandReadsSecret(command, secretName: "OTHER_TOKEN"))
    }
}

struct ClaudeGlobalConfigEditorTests {
    private static let fixture = """
        {
          "numStartups": 42,
          "autoUpdates": false,
          "projects": {"/example/project": {"allowedTools": [], "mcpServers": {}}},
          "mcpServers": {
            "example-http": {
              "type": "http",
              "url": "https://mcp.example.com/mcp",
              "headers": {"Authorization": "Bearer ${EXAMPLE_API_TOKEN}", "X-Trace": "1"}
            },
            "other-http": {"type": "http", "url": "https://other.example.com/mcp"},
            "example-stdio": {"type": "stdio", "command": "example-server", "args": ["--flag"]}
          }
        }
        """

    private func makeConfig(permissions: Int = 0o600) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("skillbox-config-\(UUID().uuidString)")

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configURL = directory.appendingPathComponent(".claude.json")

        FileManager.default.createFile(
            atPath: configURL.path, contents: Data(Self.fixture.utf8), attributes: [.posixPermissions: permissions])

        return configURL
    }

    private func readRoot(_ url: URL) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    @Test func userScopeHTTPServers_listsOnlyHTTPServers() throws {
        let configURL = try makeConfig()
        let servers = try ClaudeGlobalConfigEditor(configURL: configURL).userScopeHTTPServers()

        #expect(servers.map(\.name) == ["example-http", "other-http"])
        #expect(servers.first?.staticHeaderNames == ["Authorization", "X-Trace"])
    }

    @Test func update_changesOnlyTargetServerAndKeepsPermissions() throws {
        let configURL = try makeConfig()
        let editor = ClaudeGlobalConfigEditor(configURL: configURL)
        let before = try readRoot(configURL)

        try editor.updateUserScopeHTTPServer(named: "example-http") { $0["headersHelper"] = "example-helper" }

        let after = try readRoot(configURL)
        let servers = try #require(after["mcpServers"] as? [String: Any])
        let target = try #require(servers["example-http"] as? [String: Any])

        #expect(target["headersHelper"] as? String == "example-helper")
        #expect((target["headers"] as? [String: String])?["X-Trace"] == "1")
        #expect(
            NSDictionary(dictionary: servers["other-http"] as? [String: Any] ?? [:])
                .isEqual(to: (before["mcpServers"] as? [String: Any])?["other-http"] as? [String: Any] ?? [:]))
        #expect(after["numStartups"] as? Int == 42)
        #expect(after["autoUpdates"] as? Bool == false)
        #expect(
            NSDictionary(dictionary: after["projects"] as? [String: Any] ?? [:])
                .isEqual(to: before["projects"] as? [String: Any] ?? [:]))
        let permissions = try FileManager.default.attributesOfItem(atPath: configURL.path)[.posixPermissions] as? NSNumber

        #expect(permissions?.intValue == 0o600)
        #expect(!FileManager.default.fileExists(atPath: editor.lockDirectoryURL.path))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: configURL.deletingLastPathComponent().path)

        #expect(leftovers == [".claude.json"])
    }

    @Test func update_whileAnotherWriterHoldsTheLock_failsAndLeavesFileUnchanged() throws {
        let configURL = try makeConfig()
        var editor = ClaudeGlobalConfigEditor(configURL: configURL)

        editor.lockWaitLimit = 0.2
        try FileManager.default.createDirectory(at: editor.lockDirectoryURL, withIntermediateDirectories: false)
        let original = try Data(contentsOf: configURL)

        #expect(throws: ClaudeGlobalConfigError.configLocked) {
            try editor.updateUserScopeHTTPServer(named: "example-http") { $0["headersHelper"] = "example-helper" }
        }
        #expect(try Data(contentsOf: configURL) == original)
        #expect(FileManager.default.fileExists(atPath: editor.lockDirectoryURL.path))
    }

    @Test func update_withStaleLock_takesOverAndReleases() throws {
        let configURL = try makeConfig()
        let editor = ClaudeGlobalConfigEditor(configURL: configURL)

        try FileManager.default.createDirectory(at: editor.lockDirectoryURL, withIntermediateDirectories: false)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-60)], ofItemAtPath: editor.lockDirectoryURL.path)

        try editor.updateUserScopeHTTPServer(named: "example-http") { $0["headersHelper"] = "example-helper" }

        #expect(!FileManager.default.fileExists(atPath: editor.lockDirectoryURL.path))
    }

    @Test(arguments: ["missing-server", "example-stdio"])
    func update_unknownOrNonHTTPServer_throwsAndLeavesFileUnchanged(serverName: String) throws {
        let configURL = try makeConfig()
        let editor = ClaudeGlobalConfigEditor(configURL: configURL)
        let original = try Data(contentsOf: configURL)

        #expect(throws: ClaudeGlobalConfigError.self) {
            try editor.updateUserScopeHTTPServer(named: serverName) { $0["headersHelper"] = "example-helper" }
        }
        #expect(try Data(contentsOf: configURL) == original)
        #expect(!FileManager.default.fileExists(atPath: editor.lockDirectoryURL.path))
    }

    @Test func defaultConfigURL_respectsClaudeConfigDirectory() {
        let url = ClaudeGlobalConfigEditor.defaultConfigURL(environment: ["CLAUDE_CONFIG_DIR": "/tmp/example-claude"])

        #expect(url.path == "/tmp/example-claude/.claude.json")
    }

    @Test func connect_verifiesHelperThenInstallsItAndKeepsStaticHeaders() throws {
        let configURL = try makeConfig()
        let runner = RecordingProcessRunner()

        runner.cannedResult = ProcessRunResult(exitCode: 0, standardOutput: #"{"Authorization":"Bearer x"}"#)
        let connector = MCPSecretConnector(configEditor: ClaudeGlobalConfigEditor(configURL: configURL), processRunner: runner)

        try connector.connect(
            secretName: "EXAMPLE_API_TOKEN", serverName: "example-http", headerName: "Authorization", valuePrefix: "Bearer ")

        let server = try #require(try connector.configEditor.userScopeHTTPServers().first { $0.name == "example-http" })

        #expect(MCPSecretHeadersHelper.commandReadsSecret(server.headersHelper ?? "", secretName: "EXAMPLE_API_TOKEN"))
        #expect(server.staticHeaderNames == ["Authorization", "X-Trace"])
        #expect(runner.invocations.count == 2)
        #expect(runner.invocations.allSatisfy { $0.executablePath == "/bin/sh" })
    }

    @Test func connect_failingHelper_leavesConfigUnchanged() throws {
        let configURL = try makeConfig()
        let runner = RecordingProcessRunner()

        runner.cannedResult = ProcessRunResult(exitCode: 1, standardOutput: "")
        let connector = MCPSecretConnector(configEditor: ClaudeGlobalConfigEditor(configURL: configURL), processRunner: runner)
        let original = try Data(contentsOf: configURL)

        #expect(throws: MCPSecretHeadersHelperError.helperOutputInvalid) {
            try connector.connect(
                secretName: "EXAMPLE_API_TOKEN", serverName: "example-http", headerName: "Authorization", valuePrefix: "Bearer ")
        }
        #expect(try Data(contentsOf: configURL) == original)
    }

    @Test func connect_failingCheckAfterUpdate_restoresPreviousHelper() throws {
        let configURL = try makeConfig()
        let editor = ClaudeGlobalConfigEditor(configURL: configURL)

        try editor.updateUserScopeHTTPServer(named: "example-http") { $0["headersHelper"] = "previous-helper" }
        let runner = RecordingProcessRunner()

        runner.cannedResultSequence = [
            ProcessRunResult(exitCode: 0, standardOutput: #"{"Authorization":"Bearer x"}"#),
            ProcessRunResult(exitCode: 1, standardOutput: ""),
        ]
        let connector = MCPSecretConnector(configEditor: editor, processRunner: runner)

        #expect(throws: MCPSecretHeadersHelperError.helperOutputInvalid) {
            try connector.connect(
                secretName: "EXAMPLE_API_TOKEN", serverName: "example-http", headerName: "Authorization", valuePrefix: "Bearer ")
        }
        #expect(try editor.userScopeHTTPServers().first?.headersHelper == "previous-helper")
    }

    private static let claudeStyleFixture = #"""
        {
          "numStartups": 42,
          "tipsHistory": {
            "zeta": 1,
            "alpha": 0.1
          },
          "mcpServers": {
            "example-http": {
              "type": "http",
              "url": "https://mcp.example.com/mcp",
              "headers": {
                "Authorization": "Bearer ${EXAMPLE_API_TOKEN}",
                "X-Trace": "1"
              }
            },
            "other-http": {
              "type": "http",
              "url": "https://other.example.com/mcp"
            }
          },
          "note": "café/x",
          "ratio": 1.0
        }
        """#

    @Test func update_rewritesOnlyTheTargetServerText() throws {
        let configURL = try makeConfig()

        try Self.claudeStyleFixture.write(to: configURL, atomically: true, encoding: .utf8)
        let editor = ClaudeGlobalConfigEditor(configURL: configURL)

        try editor.updateUserScopeHTTPServer(named: "example-http") { $0["headersHelper"] = "example-helper" }
        let expectedAfterConnect = Self.claudeStyleFixture.replacingOccurrences(
            of: """
                        "X-Trace": "1"
                      }
                    },
                """,
            with: """
                        "X-Trace": "1"
                      },
                      "headersHelper": "example-helper"
                    },
                """)

        #expect(try String(contentsOf: configURL, encoding: .utf8) == expectedAfterConnect)

        try MCPSecretConnector(configEditor: editor, processRunner: RecordingProcessRunner())
            .removeStaticHeader(named: "Authorization", fromServer: "example-http")
        let expectedAfterCleanup = expectedAfterConnect.replacingOccurrences(
            of: """
                        "Authorization": "Bearer ${EXAMPLE_API_TOKEN}",

                """, with: "")

        #expect(try String(contentsOf: configURL, encoding: .utf8) == expectedAfterCleanup)
    }

    @Test func update_throughSymlink_keepsLinkAndTargetPermissions() throws {
        let targetURL = try makeConfig(permissions: 0o600)
        let linkDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("skillbox-link-\(UUID().uuidString)")

        try FileManager.default.createDirectory(at: linkDirectory, withIntermediateDirectories: true)
        let linkURL = linkDirectory.appendingPathComponent(".claude.json")

        try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: targetURL)
        let editor = ClaudeGlobalConfigEditor(configURL: linkURL)

        try editor.updateUserScopeHTTPServer(named: "example-http") { $0["headersHelper"] = "example-helper" }

        let linkType = try FileManager.default.attributesOfItem(atPath: linkURL.path)[.type] as? FileAttributeType

        #expect(linkType == .typeSymbolicLink)
        let targetPermissions = try FileManager.default.attributesOfItem(atPath: targetURL.path)[.posixPermissions] as? NSNumber

        #expect(targetPermissions?.intValue == 0o600)
        #expect(try editor.userScopeHTTPServers().first?.headersHelper == "example-helper")
        #expect(
            editor.lockDirectoryURL.deletingLastPathComponent().resolvingSymlinksInPath()
                == targetURL.deletingLastPathComponent().resolvingSymlinksInPath())
    }

    @Test func connect_whenRollbackCannotTakeTheLock_reportsRollbackFailure() throws {
        let configURL = try makeConfig()
        var editor = ClaudeGlobalConfigEditor(configURL: configURL)

        editor.lockWaitLimit = 0.2
        let runner = LockTakingProcessRunner(lockDirectoryURL: editor.lockDirectoryURL)
        let connector = MCPSecretConnector(configEditor: editor, processRunner: runner)

        #expect(throws: MCPSecretConnectorError.rollbackFailed("example-http")) {
            try connector.connect(
                secretName: "EXAMPLE_API_TOKEN", serverName: "example-http", headerName: "Authorization", valuePrefix: "Bearer ")
        }
    }

    @Test func removeStaticHeader_dropsHeaderAndEmptyMap() throws {
        let configURL = try makeConfig()
        let connector = MCPSecretConnector(
            configEditor: ClaudeGlobalConfigEditor(configURL: configURL), processRunner: RecordingProcessRunner())

        try connector.removeStaticHeader(named: "Authorization", fromServer: "example-http")
        #expect(try connector.configEditor.userScopeHTTPServers().first?.staticHeaderNames == ["X-Trace"])

        try connector.removeStaticHeader(named: "X-Trace", fromServer: "example-http")
        let servers = try #require(try readRoot(configURL)["mcpServers"] as? [String: Any])

        #expect((servers["example-http"] as? [String: Any])?["headers"] == nil)
    }
}

/// Passes the first helper check, then holds the config lock and fails the second, so the rollback cannot write.
final class LockTakingProcessRunner: ProcessRunning, @unchecked Sendable {
    private let lockDirectoryURL: URL
    private var runCount = 0

    init(lockDirectoryURL: URL) { self.lockDirectoryURL = lockDirectoryURL }

    func run(executablePath: String, arguments: [String], standardInput: String?) throws -> ProcessRunResult {
        runCount += 1
        guard runCount > 1 else { return ProcessRunResult(exitCode: 0, standardOutput: #"{"Authorization":"Bearer x"}"#) }
        try FileManager.default.createDirectory(at: lockDirectoryURL, withIntermediateDirectories: false)

        return ProcessRunResult(exitCode: 1, standardOutput: "")
    }
}
