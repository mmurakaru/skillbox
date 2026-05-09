import Foundation
import Observation

struct EnvProjectSummary: Identifiable, Hashable {
    let path: String
    let displayName: String
    let count: Int

    var id: String { path }
}

enum EnvVarStoreError: Error, LocalizedError {
    case parseFailed
    case duplicateKey(String)

    var errorDescription: String? {
        switch self {
        case .parseFailed: "Could not parse settings.json"
        case .duplicateKey(let key): "An env var named '\(key)' already exists in this scope"
        }
    }
}

/// Multi-source store: aggregates env vars from `~/.claude/settings.json` plus
/// each project's `.claude/settings.json` and `.claude/settings.local.json`.
/// Disabled vars live in `~/.claude/skillbox-env-stash.json` until re-enabled.
@MainActor
@Observable
final class EnvVarStore {
    private(set) var items: [EnvVar] = []
    private(set) var lastError: String?

    var searchQuery: String = ""

    /// nil/empty = all scopes, "global" = user global, otherwise = a project path.
    var selectedScopeKey: String?

    private var watchers: [DirectoryWatcher] = []
    private var claudeHomePath: String = ""

    init() {}

    init(seedItems: [EnvVar]) {
        self.items = Self.sort(seedItems)
    }

    func configure(claudeHomePath: String) {
        let expanded = (claudeHomePath as NSString).expandingTildeInPath
        if expanded == self.claudeHomePath { return }
        self.claudeHomePath = expanded
        rescan()
        startWatching()
    }

    func rescan() {
        let stash = EnvVarScanner.loadStash(stashURL: stashURL)
        let sources = discoverSources()
        var collected: [EnvVar] = []
        for source in sources {
            let entries = EnvVarScanner.scan(
                settingsURL: source.fileURL,
                scope: source.scope,
                stashEntries: stash[source.fileURL.path] ?? [:]
            )
            collected.append(contentsOf: entries)
        }
        self.items = Self.sort(collected)
        ensureValidSelection()
    }

    var availableProjects: [EnvProjectSummary] {
        var byPath: [String: (name: String, count: Int)] = [:]
        for item in items {
            guard let path = item.scope.projectPath else { continue }
            let name = item.scope.displayName
            byPath[path, default: (name, 0)].count += 1
            byPath[path]?.name = name
        }
        return byPath
            .map { EnvProjectSummary(path: $0.key, displayName: $0.value.name, count: $0.value.count) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    var globalCount: Int {
        items.filter {
            if case .userGlobal = $0.scope { return true }
            return false
        }.count
    }

    /// Scopes the user can target when adding a new env var. Includes User Global
    /// plus every project Claude Code knows about (`~/.claude/projects/<encoded>/`),
    /// regardless of whether `.claude/settings*.json` files exist yet.
    var addableScopes: [EnvScope] {
        guard !claudeHomePath.isEmpty else { return [.userGlobal] }
        var scopes: [EnvScope] = [.userGlobal]
        let projectsRoot = URL(fileURLWithPath: claudeHomePath).appendingPathComponent("projects")
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: projectsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var seenProjectPaths: Set<String> = []
        for projDir in entries {
            guard (try? projDir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let decoded = Memory.decodeProjectPath(projDir.lastPathComponent)
            guard FileManager.default.fileExists(atPath: decoded.full) else { continue }
            guard !seenProjectPaths.contains(decoded.full) else { continue }
            seenProjectPaths.insert(decoded.full)
            scopes.append(.project(name: decoded.last, path: decoded.full))
            scopes.append(.projectLocal(name: decoded.last, path: decoded.full))
        }
        return scopes
    }

    var filteredEnvVars: [EnvVar] {
        let scoped = items.filter { item in
            guard let key = selectedScopeKey, !key.isEmpty else { return true }
            if key == "global" {
                if case .userGlobal = item.scope { return true }
                return false
            }
            return item.scope.projectPath == key
        }
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return scoped }
        return scoped.filter { Self.matches($0, query) }
    }

    // MARK: - Mutations

    /// Move a var between settings.json and the stash without losing its value.
    func toggle(_ envVar: EnvVar) throws {
        switch envVar.state {
        case .enabled:
            try removeFromSettings(key: envVar.key, fileURL: envVar.fileURL)
            try writeStashChange(filePath: envVar.fileURL.path) { entries in
                entries[envVar.key] = envVar.value
            }
        case .disabled:
            try writeSettingsChange(fileURL: envVar.fileURL) { root in
                var env = (root["env"] as? [String: Any]) ?? [:]
                env[envVar.key] = envVar.value
                root["env"] = env
            }
            try writeStashChange(filePath: envVar.fileURL.path) { entries in
                entries.removeValue(forKey: envVar.key)
            }
        }
        rescan()
    }

    /// Permanently remove from settings.json AND the stash.
    func delete(_ envVar: EnvVar) throws {
        try? removeFromSettings(key: envVar.key, fileURL: envVar.fileURL)
        try writeStashChange(filePath: envVar.fileURL.path) { entries in
            entries.removeValue(forKey: envVar.key)
        }
        rescan()
    }

    /// Add a brand-new env var. Creates the settings.json file if missing.
    /// Throws `.duplicateKey` if the key already exists in that scope (enabled or disabled).
    func add(key: String, value: String, scope: EnvScope) throws {
        let fileURL = settingsURL(for: scope)

        // Check for collisions against current state.
        if items.contains(where: { $0.fileURL.path == fileURL.path && $0.key == key }) {
            throw EnvVarStoreError.duplicateKey(key)
        }

        try ensureParentDirectory(for: fileURL)
        try writeSettingsChange(fileURL: fileURL) { root in
            var env = (root["env"] as? [String: Any]) ?? [:]
            env[key] = value
            root["env"] = env
        }
        rescan()
    }

    // MARK: - Internals (exposed for tests)

    var stashURL: URL {
        URL(fileURLWithPath: claudeHomePath).appendingPathComponent("skillbox-env-stash.json")
    }

    func settingsURL(for scope: EnvScope) -> URL {
        switch scope {
        case .userGlobal:
            return URL(fileURLWithPath: claudeHomePath).appendingPathComponent("settings.json")
        case .project(_, let path):
            return URL(fileURLWithPath: path)
                .appendingPathComponent(".claude")
                .appendingPathComponent("settings.json")
        case .projectLocal(_, let path):
            return URL(fileURLWithPath: path)
                .appendingPathComponent(".claude")
                .appendingPathComponent("settings.local.json")
        }
    }

    /// Remove `key` from settings.json's `env` block. Collapse `env` if empty.
    /// If the file doesn't exist or has no env block, this is a no-op.
    func removeFromSettings(key: String, fileURL: URL) throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        let data = try Data(contentsOf: fileURL)
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw EnvVarStoreError.parseFailed
        }
        var env = (root["env"] as? [String: Any]) ?? [:]
        env.removeValue(forKey: key)
        if env.isEmpty {
            root.removeValue(forKey: "env")
        } else {
            root["env"] = env
        }
        let out = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .withoutEscapingSlashes]
        )
        try out.write(to: fileURL, options: .atomic)
    }

    /// Read settings.json (or treat as `{}` if missing), apply mutation, write back.
    func writeSettingsChange(fileURL: URL, _ mutate: (inout [String: Any]) -> Void) throws {
        var root: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let data = try Data(contentsOf: fileURL)
            if let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                root = parsed
            } else {
                throw EnvVarStoreError.parseFailed
            }
        }
        mutate(&root)
        let out = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .withoutEscapingSlashes]
        )
        try out.write(to: fileURL, options: .atomic)
    }

    /// Read stash (or `{:}` if missing), mutate one file's entry map, write back.
    /// Drops empty entry maps to keep the stash tidy.
    func writeStashChange(filePath: String, _ mutate: (inout [String: String]) -> Void) throws {
        var stash = EnvVarScanner.loadStash(stashURL: stashURL)
        var entries = stash[filePath] ?? [:]
        mutate(&entries)
        if entries.isEmpty {
            stash.removeValue(forKey: filePath)
        } else {
            stash[filePath] = entries
        }
        let asAny: [String: Any] = stash.reduce(into: [:]) { $0[$1.key] = $1.value }
        let out = try JSONSerialization.data(
            withJSONObject: asAny,
            options: [.prettyPrinted, .withoutEscapingSlashes]
        )
        try out.write(to: stashURL, options: .atomic)
    }

    private func ensureParentDirectory(for fileURL: URL) throws {
        let parent = fileURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parent.path) {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        }
    }

    // MARK: - Discovery & watching

    private struct EnvSource {
        let fileURL: URL
        let scope: EnvScope
    }

    private func discoverSources() -> [EnvSource] {
        guard !claudeHomePath.isEmpty else { return [] }
        let fm = FileManager.default
        var sources: [EnvSource] = []

        let home = URL(fileURLWithPath: claudeHomePath)
        let globalSettings = home.appendingPathComponent("settings.json")
        if fm.fileExists(atPath: globalSettings.path) {
            sources.append(EnvSource(fileURL: globalSettings, scope: .userGlobal))
        }

        let projectsRoot = home.appendingPathComponent("projects")
        guard fm.fileExists(atPath: projectsRoot.path) else { return sources }

        let entries = (try? fm.contentsOfDirectory(
            at: projectsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        for projDir in entries {
            guard (try? projDir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let decoded = Memory.decodeProjectPath(projDir.lastPathComponent)
            let claudeDir = URL(fileURLWithPath: decoded.full).appendingPathComponent(".claude")

            let committed = claudeDir.appendingPathComponent("settings.json")
            if fm.fileExists(atPath: committed.path) {
                sources.append(EnvSource(
                    fileURL: committed,
                    scope: .project(name: decoded.last, path: decoded.full)
                ))
            }
            let local = claudeDir.appendingPathComponent("settings.local.json")
            if fm.fileExists(atPath: local.path) {
                sources.append(EnvSource(
                    fileURL: local,
                    scope: .projectLocal(name: decoded.last, path: decoded.full)
                ))
            }
        }
        return sources
    }

    private func startWatching() {
        watchers.removeAll()
        let onChange: () -> Void = { [weak self] in
            Task { @MainActor in self?.rescan() }
        }

        let home = URL(fileURLWithPath: claudeHomePath)
        if let w = DirectoryWatcher(url: home, onChange: onChange) {
            watchers.append(w)
        }
        let projectsRoot = home.appendingPathComponent("projects")
        if FileManager.default.fileExists(atPath: projectsRoot.path),
           let w = DirectoryWatcher(url: projectsRoot, onChange: onChange) {
            watchers.append(w)
        }
        for source in discoverSources() {
            if let w = DirectoryWatcher(url: source.fileURL, onChange: onChange) {
                watchers.append(w)
            }
        }
        if FileManager.default.fileExists(atPath: stashURL.path),
           let w = DirectoryWatcher(url: stashURL, onChange: onChange) {
            watchers.append(w)
        }
    }

    private func ensureValidSelection() {
        guard let key = selectedScopeKey, !key.isEmpty else { return }
        if key == "global" {
            if globalCount == 0 { selectedScopeKey = nil }
            return
        }
        if !availableProjects.contains(where: { $0.path == key }) {
            selectedScopeKey = nil
        }
    }

    private static func matches(_ item: EnvVar, _ query: String) -> Bool {
        if item.key.localizedCaseInsensitiveContains(query) { return true }
        if item.value.localizedCaseInsensitiveContains(query) { return true }
        if let desc = EnvVarCatalog.description(for: item.key),
           desc.localizedCaseInsensitiveContains(query) { return true }
        return false
    }

    private static func sort(_ items: [EnvVar]) -> [EnvVar] {
        items.sorted { lhs, rhs in
            if lhs.key != rhs.key {
                return lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending
            }
            return scopeRank(lhs.scope) < scopeRank(rhs.scope)
        }
    }

    private static func scopeRank(_ scope: EnvScope) -> Int {
        switch scope {
        case .userGlobal: 0
        case .project: 1
        case .projectLocal: 2
        }
    }
}
