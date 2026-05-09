import Foundation
import Observation

struct HookProjectSummary: Identifiable, Hashable {
    let path: String
    let displayName: String
    let count: Int

    var id: String { path }
}

enum HookStoreError: Error, LocalizedError {
    case parseFailed
    case invalidPointer

    var errorDescription: String? {
        switch self {
        case .parseFailed: "Could not parse settings.json"
        case .invalidPointer: "Could not locate hook entry to delete"
        }
    }
}

/// Multi-source store: aggregates hooks from `~/.claude/settings.json` plus
/// each project's `.claude/settings.json` and `.claude/settings.local.json`.
/// Cannot reuse `FileBackedItemStore` because that watches a single root;
/// hooks come from N files across N roots.
@MainActor
@Observable
final class HookStore {
    private(set) var items: [Hook] = []
    private(set) var lastError: String?

    var searchQuery: String = ""

    /// nil/empty = all scopes, "global" = user global, otherwise = a project path.
    var selectedScopeKey: String?

    private var watchers: [DirectoryWatcher] = []
    private var claudeHomePath: String = ""

    init() {}

    init(seedHooks: [Hook]) {
        self.items = Self.sort(seedHooks)
    }

    func configure(claudeHomePath: String) {
        let expanded = (claudeHomePath as NSString).expandingTildeInPath
        if expanded == self.claudeHomePath { return }
        self.claudeHomePath = expanded
        rescan()
        startWatching()
    }

    func rescan() {
        let sources = discoverSources()
        var collected: [Hook] = []
        var firstError: String?
        for source in sources {
            do {
                let entries = try HookScanner.scan(fileURL: source.fileURL, scope: source.scope)
                collected.append(contentsOf: entries)
            } catch {
                if firstError == nil {
                    firstError = "\(source.fileURL.lastPathComponent): \(error.localizedDescription)"
                }
            }
        }
        self.items = Self.sort(collected)
        self.lastError = firstError
        ensureValidSelection()
    }

    var availableProjects: [HookProjectSummary] {
        var byPath: [String: (name: String, count: Int)] = [:]
        for hook in items {
            guard let path = hook.scope.projectPath else { continue }
            let name = hook.scope.displayName
            byPath[path, default: (name, 0)].count += 1
            byPath[path]?.name = name
        }
        return byPath
            .map { HookProjectSummary(path: $0.key, displayName: $0.value.name, count: $0.value.count) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    var globalHookCount: Int {
        items.filter {
            if case .userGlobal = $0.scope { return true }
            return false
        }.count
    }

    var filteredHooks: [Hook] {
        let scoped = items.filter { hook in
            guard let key = selectedScopeKey, !key.isEmpty else { return true }
            if key == "global" {
                if case .userGlobal = hook.scope { return true }
                return false
            }
            return hook.scope.projectPath == key
        }
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return scoped }
        return scoped.filter { Self.matches($0, query) }
    }

    func remove(_ hook: Hook) {
        items.removeAll { $0.id == hook.id }
    }

    /// Deletes one hook entry from its parent settings.json, collapsing now-empty
    /// rule groups, event arrays, and the top-level `hooks` object as it goes.
    func delete(_ hook: Hook) throws {
        let url = hook.fileURL
        let data = try Data(contentsOf: url)
        guard var root = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            throw HookStoreError.parseFailed
        }
        try Self.deleteAtPointer(in: &root, pointer: hook.jsonPointer)
        let out = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .withoutEscapingSlashes]
        )
        try out.write(to: url, options: .atomic)
        rescan()
    }

    // MARK: - Internal (exposed for tests)

    static func deleteAtPointer(in root: inout [String: Any], pointer: String) throws {
        let tokens = pointer
            .split(separator: "/", omittingEmptySubsequences: false)
            .dropFirst()  // leading empty from "/hooks/..."
            .map { Self.unescape(String($0)) }

        guard tokens.count == 5,
              tokens[0] == "hooks",
              tokens[3] == "hooks",
              let ruleIdx = Int(tokens[2]),
              let innerIdx = Int(tokens[4]) else {
            throw HookStoreError.invalidPointer
        }
        let eventKey = tokens[1]

        guard var hooksMap = root["hooks"] as? [String: Any],
              var ruleGroups = hooksMap[eventKey] as? [Any],
              ruleGroups.indices.contains(ruleIdx),
              var rule = ruleGroups[ruleIdx] as? [String: Any],
              var inner = rule["hooks"] as? [Any],
              inner.indices.contains(innerIdx) else {
            throw HookStoreError.invalidPointer
        }

        inner.remove(at: innerIdx)
        if inner.isEmpty {
            ruleGroups.remove(at: ruleIdx)
        } else {
            rule["hooks"] = inner
            ruleGroups[ruleIdx] = rule
        }
        if ruleGroups.isEmpty {
            hooksMap.removeValue(forKey: eventKey)
        } else {
            hooksMap[eventKey] = ruleGroups
        }
        if hooksMap.isEmpty {
            root.removeValue(forKey: "hooks")
        } else {
            root["hooks"] = hooksMap
        }
    }

    // MARK: - Private

    private struct HookSource {
        let fileURL: URL
        let scope: HookScope
    }

    private func discoverSources() -> [HookSource] {
        guard !claudeHomePath.isEmpty else { return [] }
        let fm = FileManager.default
        var sources: [HookSource] = []
        // Dedupe by absolute file path - some encoded "projects" decode to the
        // user's home dir, where `.claude/settings.json` IS the global file. We'd
        // otherwise scan the same hook twice (once Global, once Project), and the
        // duplicate ids confuse the ForEach.
        var seenPaths: Set<String> = []

        let home = URL(fileURLWithPath: claudeHomePath)
        let globalSettings = home.appendingPathComponent("settings.json")
        if fm.fileExists(atPath: globalSettings.path) {
            sources.append(HookSource(fileURL: globalSettings, scope: .userGlobal))
            seenPaths.insert(globalSettings.path)
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
            if fm.fileExists(atPath: committed.path), !seenPaths.contains(committed.path) {
                sources.append(HookSource(
                    fileURL: committed,
                    scope: .project(name: decoded.last, path: decoded.full)
                ))
                seenPaths.insert(committed.path)
            }
            let local = claudeDir.appendingPathComponent("settings.local.json")
            if fm.fileExists(atPath: local.path), !seenPaths.contains(local.path) {
                sources.append(HookSource(
                    fileURL: local,
                    scope: .projectLocal(name: decoded.last, path: decoded.full)
                ))
                seenPaths.insert(local.path)
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
        // Also watch each known settings.json so in-place edits trigger rescan.
        for source in discoverSources() {
            if let w = DirectoryWatcher(url: source.fileURL, onChange: onChange) {
                watchers.append(w)
            }
        }
    }

    private func ensureValidSelection() {
        guard let key = selectedScopeKey, !key.isEmpty else { return }
        if key == "global" {
            if globalHookCount == 0 { selectedScopeKey = nil }
            return
        }
        if !availableProjects.contains(where: { $0.path == key }) {
            selectedScopeKey = nil
        }
    }

    private static func matches(_ hook: Hook, _ query: String) -> Bool {
        hook.eventName.displayLabel.localizedCaseInsensitiveContains(query) ||
        (hook.matcher ?? "").localizedCaseInsensitiveContains(query) ||
        hook.payload.localizedCaseInsensitiveContains(query) ||
        hook.kind.displayLabel.localizedCaseInsensitiveContains(query)
    }

    private static func sort(_ hooks: [Hook]) -> [Hook] {
        hooks.sorted { lhs, rhs in
            if lhs.eventName.sortKey.0 != rhs.eventName.sortKey.0 {
                return lhs.eventName.sortKey.0 < rhs.eventName.sortKey.0
            }
            if lhs.eventName.sortKey.1 != rhs.eventName.sortKey.1 {
                return lhs.eventName.sortKey.1 < rhs.eventName.sortKey.1
            }
            return (lhs.matcher ?? "") < (rhs.matcher ?? "")
        }
    }

    private static func unescape(_ token: String) -> String {
        token
            .replacingOccurrences(of: "~1", with: "/")
            .replacingOccurrences(of: "~0", with: "~")
    }
}
