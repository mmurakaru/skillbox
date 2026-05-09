import Testing
import Foundation
@testable import Skillbox

struct EnvVarScannerTests {
    private func makeFixture() throws -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("skillbox-env-scanner-\(UUID().uuidString).json")
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func write(_ json: String, to url: URL) throws {
        try json.write(to: url, atomically: true, encoding: .utf8)
    }

    @Test func scan_settingsWithoutEnv_returnsEmpty() throws {
        let url = try makeFixture()
        defer { cleanup(url) }
        try write(#"{"theme": "dark"}"#, to: url)
        let result = EnvVarScanner.scan(settingsURL: url, scope: .userGlobal, stashEntries: [:])
        #expect(result.isEmpty)
    }

    @Test func scan_missingFile_withStashEntries_yieldsDisabledRows() throws {
        let url = try makeFixture()
        // Don't write the file - it doesn't exist.
        let result = EnvVarScanner.scan(
            settingsURL: url,
            scope: .userGlobal,
            stashEntries: ["FOO": "1"]
        )
        #expect(result.count == 1)
        let entry = try #require(result.first)
        #expect(entry.key == "FOO")
        #expect(entry.value == "1")
        #expect(entry.state == .disabled)
    }

    @Test func scan_basicEnv_yieldsEnabledRows() throws {
        let url = try makeFixture()
        defer { cleanup(url) }
        try write(#"""
        {
          "env": {
            "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1",
            "API_TIMEOUT_MS": "60000"
          }
        }
        """#, to: url)
        let result = EnvVarScanner.scan(settingsURL: url, scope: .userGlobal, stashEntries: [:])
        #expect(result.count == 2)
        let keys = Set(result.map(\.key))
        #expect(keys == ["CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS", "API_TIMEOUT_MS"])
        #expect(result.allSatisfy { $0.state == .enabled })
    }

    @Test func scan_settingsWinsOverStash_whenKeyAppearsInBoth() throws {
        let url = try makeFixture()
        defer { cleanup(url) }
        try write(#"{"env": {"DEBUG": "active"}}"#, to: url)
        let result = EnvVarScanner.scan(
            settingsURL: url,
            scope: .userGlobal,
            stashEntries: ["DEBUG": "stashed"]
        )
        #expect(result.count == 1)
        let entry = try #require(result.first)
        #expect(entry.state == .enabled)
        #expect(entry.value == "active")
    }

    @Test func scan_separateKeysInBoth_yieldsBothEnabledAndDisabled() throws {
        let url = try makeFixture()
        defer { cleanup(url) }
        try write(#"{"env": {"ENABLED_VAR": "1"}}"#, to: url)
        let result = EnvVarScanner.scan(
            settingsURL: url,
            scope: .userGlobal,
            stashEntries: ["DISABLED_VAR": "stashed"]
        )
        #expect(result.count == 2)
        let byKey = Dictionary(uniqueKeysWithValues: result.map { ($0.key, $0.state) })
        #expect(byKey["ENABLED_VAR"] == .enabled)
        #expect(byKey["DISABLED_VAR"] == .disabled)
    }

    @Test func scan_coercesNumericAndBooleanValuesToStrings() throws {
        let url = try makeFixture()
        defer { cleanup(url) }
        try write(#"""
        {"env": {"MAX_RETRIES": 5, "ENABLED": true}}
        """#, to: url)
        let result = EnvVarScanner.scan(settingsURL: url, scope: .userGlobal, stashEntries: [:])
        let byKey = Dictionary(uniqueKeysWithValues: result.map { ($0.key, $0.value) })
        #expect(byKey["MAX_RETRIES"] == "5")
        #expect(byKey["ENABLED"] == "true")
    }

    @Test func loadStash_missingFile_returnsEmpty() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("skillbox-env-stash-missing-\(UUID().uuidString).json")
        let stash = EnvVarScanner.loadStash(stashURL: url)
        #expect(stash.isEmpty)
    }

    @Test func loadStash_validFile_parsesNestedShape() throws {
        let url = try makeFixture()
        defer { cleanup(url) }
        try write(#"""
        {
          "/Users/me/.claude/settings.json": {
            "FOO": "1",
            "BAR": "two"
          }
        }
        """#, to: url)
        let stash = EnvVarScanner.loadStash(stashURL: url)
        #expect(stash.count == 1)
        let entries = try #require(stash["/Users/me/.claude/settings.json"])
        #expect(entries["FOO"] == "1")
        #expect(entries["BAR"] == "two")
    }
}
