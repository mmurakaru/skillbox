import Testing
import Foundation
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
        #expect(parsed?["env"] == nil) // env block collapsed because empty

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
        #expect(reloadedStash[settings.path] == nil) // entry removed; map collapsed

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
