import Foundation
import Testing

@testable import Skillbox

@MainActor
struct EnvVarStoreTests {
    private func makeEnvVar(
        key: String = "FOO",
        value: String = "1",
        state: EnvVarState = .enabled,
        scope: EnvScope = .userGlobal,
        fileURL: URL = URL(fileURLWithPath: "/tmp/settings.json")
    ) -> EnvVar {
        EnvVar(key: key, value: value, state: state, scope: scope, fileURL: fileURL, modifiedAt: Date())
    }

    // MARK: - filteredEnvVars

    @Test func filtered_emptyQueryNoSelection_returnsAll() {
        let store = EnvVarStore(seedItems: [
            makeEnvVar(key: "A"),
            makeEnvVar(key: "B"),
        ])

        #expect(store.filteredEnvVars.count == 2)
    }

    @Test func filtered_globalScope_returnsOnlyGlobal() {
        let store = EnvVarStore(seedItems: [
            makeEnvVar(key: "GLOBAL_VAR", scope: .userGlobal),
            makeEnvVar(
                key: "PROJECT_VAR",
                scope: .project(name: "alpha", path: "/p/alpha"),
                fileURL: URL(fileURLWithPath: "/p/alpha/.claude/settings.json")
            ),
        ])

        store.selectedScopeKey = "global"
        #expect(store.filteredEnvVars.map(\.key) == ["GLOBAL_VAR"])
    }

    @Test func filtered_projectScope_includesBothCommittedAndLocal() {
        let path = "/p/alpha"
        let store = EnvVarStore(seedItems: [
            makeEnvVar(key: "X", scope: .project(name: "alpha", path: path)),
            makeEnvVar(key: "Y", scope: .projectLocal(name: "alpha", path: path)),
            makeEnvVar(key: "G", scope: .userGlobal),
        ])

        store.selectedScopeKey = path
        let keys = store.filteredEnvVars.map(\.key).sorted()

        #expect(keys == ["X", "Y"])
    }

    @Test func filtered_searchByKey_isCaseInsensitive() {
        let store = EnvVarStore(seedItems: [
            makeEnvVar(key: "API_TIMEOUT_MS"),
            makeEnvVar(key: "DEBUG_LEVEL"),
        ])

        store.searchQuery = "timeout"
        #expect(store.filteredEnvVars.map(\.key) == ["API_TIMEOUT_MS"])
    }

    @Test func filtered_searchByValue_matches() {
        let store = EnvVarStore(seedItems: [
            makeEnvVar(key: "A", value: "redis://host"),
            makeEnvVar(key: "B", value: "postgres://host"),
        ])

        store.searchQuery = "redis"
        #expect(store.filteredEnvVars.map(\.key) == ["A"])
    }

    @Test func filtered_searchByCatalogDescription_findsKnownVar() {
        let store = EnvVarStore(seedItems: [
            makeEnvVar(key: "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS"),
            makeEnvVar(key: "OTHER_VAR"),
        ])

        store.searchQuery = "agent teams"
        #expect(store.filteredEnvVars.map(\.key) == ["CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS"])
    }

    // MARK: - Catalog

    @Test func catalog_descriptionLookup_returnsDescriptionForKnown() {
        let desc = EnvVarCatalog.description(for: "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS")

        #expect(desc != nil)
    }

    @Test func catalog_descriptionLookup_returnsNilForUnknown() {
        #expect(EnvVarCatalog.description(for: "TOTALLY_INVENTED_VAR") == nil)
    }

    @Test func catalog_suggestions_matchPrefix() {
        let results = EnvVarCatalog.suggestions(matching: "CLAUDE_CODE_EXPER")

        #expect(results.contains(where: { $0.key == "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS" }))
    }

    @Test func catalog_suggestions_emptyQueryReturnsEmpty() {
        #expect(EnvVarCatalog.suggestions(matching: "").isEmpty)
    }

    // MARK: - File mutation primitives (round-trip via real temp dir)

    private func makeTempHome() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("skillbox-envstore-\(UUID().uuidString)")

        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        return url
    }

    @Test func toggle_enabledToDisabled_movesValueToStash() async throws {
        let home = try makeTempHome()

        defer { try? FileManager.default.removeItem(at: home) }

        let settings = home.appendingPathComponent("settings.json")

        try #"""
        {"env": {"FOO": "1"}}
        """#.write(to: settings, atomically: true, encoding: .utf8)

        let store = EnvVarStore()

        store.configure(claudeHomePath: home.path)
        let foo = try #require(store.items.first)

        #expect(foo.state == .enabled)

        try store.toggle(foo)

        let parsed = try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? [String: Any]

        #expect(parsed?["env"] == nil)  // env block collapsed because empty

        let stash = EnvVarScanner.loadStash(stashURL: store.stashURL)

        #expect(stash[settings.path]?["FOO"] == "1")

        // Item now appears as disabled.
        #expect(store.items.first?.state == .disabled)
        #expect(store.items.first?.value == "1")
    }

    @Test func toggle_disabledToEnabled_movesValueBackToSettings() async throws {
        let home = try makeTempHome()

        defer { try? FileManager.default.removeItem(at: home) }

        let settings = home.appendingPathComponent("settings.json")

        try "{}".write(to: settings, atomically: true, encoding: .utf8)
        let stash = home.appendingPathComponent("skillbox-env-stash.json")

        try #"""
        {"\#(settings.path)": {"FOO": "1"}}
        """#.write(to: stash, atomically: true, encoding: .utf8)

        let store = EnvVarStore()

        store.configure(claudeHomePath: home.path)
        let foo = try #require(store.items.first)

        #expect(foo.state == .disabled)

        try store.toggle(foo)

        let parsed = try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? [String: Any]
        let env = try #require(parsed?["env"] as? [String: Any])

        #expect(env["FOO"] as? String == "1")

        let reloadedStash = EnvVarScanner.loadStash(stashURL: stash)

        #expect(reloadedStash[settings.path] == nil)  // entry removed; map collapsed

        #expect(store.items.first?.state == .enabled)
    }

    @Test func add_writesToSettings_andCreatesEnvBlockIfMissing() async throws {
        let home = try makeTempHome()

        defer { try? FileManager.default.removeItem(at: home) }

        let store = EnvVarStore()

        store.configure(claudeHomePath: home.path)

        try store.add(key: "NEW_VAR", value: "yes", scope: .userGlobal)

        let settings = home.appendingPathComponent("settings.json")
        let parsed = try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? [String: Any]
        let env = try #require(parsed?["env"] as? [String: Any])

        #expect(env["NEW_VAR"] as? String == "yes")
        #expect(store.items.contains(where: { $0.key == "NEW_VAR" && $0.isEnabled }))
    }

    @Test func add_duplicateKey_throws() async throws {
        let home = try makeTempHome()

        defer { try? FileManager.default.removeItem(at: home) }

        let settings = home.appendingPathComponent("settings.json")

        try #"{"env": {"DUP": "old"}}"#.write(to: settings, atomically: true, encoding: .utf8)

        let store = EnvVarStore()

        store.configure(claudeHomePath: home.path)

        #expect(throws: EnvVarStoreError.self) {
            try store.add(key: "DUP", value: "new", scope: .userGlobal)
        }
    }

    @Test func delete_removesFromBothSettingsAndStash() async throws {
        let home = try makeTempHome()

        defer { try? FileManager.default.removeItem(at: home) }

        let settings = home.appendingPathComponent("settings.json")

        try #"{"env": {"DOOMED": "x", "SURVIVOR": "y"}}"#
            .write(to: settings, atomically: true, encoding: .utf8)

        let stash = home.appendingPathComponent("skillbox-env-stash.json")

        try #"""
        {"\#(settings.path)": {"DOOMED": "x"}}
        """#.write(to: stash, atomically: true, encoding: .utf8)

        let store = EnvVarStore()

        store.configure(claudeHomePath: home.path)
        let doomed = try #require(store.items.first(where: { $0.key == "DOOMED" }))

        try store.delete(doomed)

        let parsed = try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? [String: Any]
        let env = try #require(parsed?["env"] as? [String: Any])

        #expect(env["DOOMED"] == nil)
        #expect(env["SURVIVOR"] as? String == "y")

        let reloaded = EnvVarScanner.loadStash(stashURL: stash)

        #expect(reloaded[settings.path] == nil)

        #expect(!store.items.contains(where: { $0.key == "DOOMED" }))
    }

    // MARK: - Secrets

    @Test func rescan_flagsSecretsByNameRule() throws {
        let home = try makeTempHome()

        defer { try? FileManager.default.removeItem(at: home) }
        try #"{"env": {"EXAMPLE_API_TOKEN": "abc", "PLAIN_FLAG": "1"}}"#
            .write(to: home.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)

        let store = EnvVarStore()

        store.configure(claudeHomePath: home.path)

        #expect(store.items.first(where: { $0.key == "EXAMPLE_API_TOKEN" })?.isSecret == true)
        #expect(store.items.first(where: { $0.key == "PLAIN_FLAG" })?.isSecret == false)
    }

    @Test func toggle_disablingSecret_removesValueWithoutStashing() throws {
        let home = try makeTempHome()

        defer { try? FileManager.default.removeItem(at: home) }
        let settings = home.appendingPathComponent("settings.json")

        try #"{"env": {"EXAMPLE_API_TOKEN": "abc", "PLAIN_FLAG": "1"}}"#
            .write(to: settings, atomically: true, encoding: .utf8)

        let store = EnvVarStore()

        store.configure(claudeHomePath: home.path)
        let secret = try #require(store.items.first(where: { $0.key == "EXAMPLE_API_TOKEN" }))

        try store.toggle(secret)

        let parsed = try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? [String: Any]
        let env = try #require(parsed?["env"] as? [String: Any])

        #expect(env["EXAMPLE_API_TOKEN"] == nil)
        #expect(env["PLAIN_FLAG"] as? String == "1")
        #expect(!FileManager.default.fileExists(atPath: store.stashURL.path))
        #expect(!store.items.contains(where: { $0.key == "EXAMPLE_API_TOKEN" }))
    }

    @Test func add_secretToSharedProjectScope_throwsAndWritesNothing() throws {
        let home = try makeTempHome()

        defer { try? FileManager.default.removeItem(at: home) }
        let project = home.appendingPathComponent("example-project")
        let store = EnvVarStore()

        store.configure(claudeHomePath: home.path)
        let sharedScope = EnvScope.project(name: "example-project", path: project.path)

        #expect(throws: EnvVarStoreError.self) {
            try store.add(key: "EXAMPLE_API_TOKEN", value: "abc", scope: sharedScope)
        }
        try store.setSecretMark(true, forName: "DATABASE_URL")
        #expect(throws: EnvVarStoreError.self) {
            try store.add(key: "DATABASE_URL", value: "abc", scope: sharedScope)
        }
        #expect(!FileManager.default.fileExists(atPath: store.settingsURL(for: sharedScope).path))
    }

    @Test func add_secretToLocalProjectScope_isAllowed() throws {
        let home = try makeTempHome()

        defer { try? FileManager.default.removeItem(at: home) }
        let project = home.appendingPathComponent("example-project")
        let store = EnvVarStore()

        store.configure(claudeHomePath: home.path)
        let localScope = EnvScope.projectLocal(name: "example-project", path: project.path)

        try store.add(key: "EXAMPLE_API_TOKEN", value: "abc", scope: localScope)

        let parsed = try JSONSerialization.jsonObject(with: Data(contentsOf: store.settingsURL(for: localScope))) as? [String: Any]

        #expect((parsed?["env"] as? [String: Any])?["EXAMPLE_API_TOKEN"] as? String == "abc")
    }

    @Test func setSecretMark_persistsMarkAndFlagsItem() throws {
        let home = try makeTempHome()

        defer { try? FileManager.default.removeItem(at: home) }
        try #"{"env": {"DATABASE_URL": "postgres://example"}}"#
            .write(to: home.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
        let store = EnvVarStore()

        store.configure(claudeHomePath: home.path)

        try store.setSecretMark(true, forName: "DATABASE_URL")

        #expect(store.markedSecretNames == ["DATABASE_URL"])
        #expect(store.items.first(where: { $0.key == "DATABASE_URL" })?.isSecret == true)

        try store.setSecretMark(false, forName: "DATABASE_URL")
        #expect(store.items.first(where: { $0.key == "DATABASE_URL" })?.isSecret == false)
    }

    @Test func setSecretMark_onVarInSharedProjectScope_throws() {
        let store = EnvVarStore(seedItems: [
            makeEnvVar(
                key: "DATABASE_URL",
                scope: .project(name: "example-project", path: "/p/example-project"),
                fileURL: URL(fileURLWithPath: "/p/example-project/.claude/settings.json")
            )
        ])

        #expect(throws: EnvVarStoreError.self) {
            try store.setSecretMark(true, forName: "DATABASE_URL")
        }
    }

    @Test func setSecretMark_onDisabledVar_throwsSoTheStashedValueIsNotOrphaned() {
        let store = EnvVarStore(seedItems: [makeEnvVar(key: "DATABASE_URL", state: .disabled)])

        #expect(throws: EnvVarStoreError.self) {
            try store.setSecretMark(true, forName: "DATABASE_URL")
        }
    }

    @Test func filtered_searchBySecretValue_doesNotMatch() {
        var secret = makeEnvVar(key: "EXAMPLE_API_TOKEN", value: "needle-value")

        secret.isSecret = true
        let store = EnvVarStore(seedItems: [secret, makeEnvVar(key: "PLAIN", value: "needle-value")])

        store.searchQuery = "needle"
        #expect(store.filteredEnvVars.map(\.key) == ["PLAIN"])
    }

    @Test func rescan_leavesExistingStashedSecretUntouched() throws {
        let home = try makeTempHome()

        defer { try? FileManager.default.removeItem(at: home) }
        let settings = home.appendingPathComponent("settings.json")

        try "{}".write(to: settings, atomically: true, encoding: .utf8)
        let stash = home.appendingPathComponent("skillbox-env-stash.json")
        let stashContents = #"{"\#(settings.path)": {"EXAMPLE_API_TOKEN": "abc"}}"#

        try stashContents.write(to: stash, atomically: true, encoding: .utf8)

        let store = EnvVarStore()

        store.configure(claudeHomePath: home.path)

        let stashed = try #require(store.items.first)

        #expect(stashed.isSecret && stashed.state == .disabled)
        #expect(store.stashedSecrets.map(\.key) == ["EXAMPLE_API_TOKEN"])
        #expect(try String(contentsOf: stash, encoding: .utf8) == stashContents)
    }

    @Test func purgeStashedSecrets_removesOnlySecretStashEntries() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let settings = home.appendingPathComponent("settings.json")
        try "{}".write(to: settings, atomically: true, encoding: .utf8)
        let stash = home.appendingPathComponent("skillbox-env-stash.json")
        try #"{"\#(settings.path)": {"EXAMPLE_API_TOKEN": "abc", "EXAMPLE_FLAG": "1"}}"#
            .write(to: stash, atomically: true, encoding: .utf8)
        let store = EnvVarStore()
        store.configure(claudeHomePath: home.path)

        try store.purgeStashedSecrets()

        #expect(EnvVarScanner.loadStash(stashURL: store.stashURL)[settings.path] == ["EXAMPLE_FLAG": "1"])
        #expect(store.stashedSecrets.isEmpty)
        #expect(store.items.map(\.key) == ["EXAMPLE_FLAG"])
    }

    @Test func toggle_offCollapsesEmptyEnvBlock_butLeavesOtherKeys() async throws {
        let home = try makeTempHome()

        defer { try? FileManager.default.removeItem(at: home) }

        let settings = home.appendingPathComponent("settings.json")

        try #"""
        {"theme": "dark", "env": {"ONLY_VAR": "1"}}
        """#.write(to: settings, atomically: true, encoding: .utf8)

        let store = EnvVarStore()

        store.configure(claudeHomePath: home.path)
        let only = try #require(store.items.first)

        try store.toggle(only)

        let parsed = try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? [String: Any]

        #expect(parsed?["env"] == nil)
        #expect(parsed?["theme"] as? String == "dark")
    }
}
