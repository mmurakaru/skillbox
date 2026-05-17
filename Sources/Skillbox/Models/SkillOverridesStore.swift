import Foundation
import Observation

/// Reads and writes the `skillOverrides` map in `~/.claude/settings.json`.
/// Watches the file so external edits (e.g. via `/skills` in Claude Code) reflect live.
@MainActor
@Observable
final class SkillOverridesStore {
    private(set) var overrides: [String: SkillOverride] = [:]
    private(set) var lastError: String?

    private var settingsURL: URL = URL(fileURLWithPath: "")
    private var watcher: DirectoryWatcher?

    init() {}

    func configure(claudeHomePath: String) {
        let expanded = (claudeHomePath as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded).appendingPathComponent("settings.json")
        if url == settingsURL { return }
        settingsURL = url
        refresh()
        startWatching()
    }

    func refresh() {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else {
            overrides = [:]
            lastError = nil
            return
        }
        do {
            let data = try Data(contentsOf: settingsURL)
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                overrides = [:]
                lastError = "settings.json is not a JSON object"
                return
            }
            let raw = (root["skillOverrides"] as? [String: String]) ?? [:]
            overrides = raw.compactMapValues { SkillOverride(rawValue: $0) }
            lastError = nil
        } catch {
            overrides = [:]
            lastError = "Failed to read settings.json: \(error.localizedDescription)"
        }
    }

    /// Current state for `name`, defaulting to `.on` when absent.
    func state(for name: String) -> SkillOverride {
        overrides[name] ?? .on
    }

    /// Writes the new state. Removes the key entirely when value is `.on` to keep the map tidy.
    func set(_ name: String, to state: SkillOverride) throws {
        try writeSettingsChange { root in
            var map = (root["skillOverrides"] as? [String: String]) ?? [:]
            if state == .on {
                map.removeValue(forKey: name)
            } else {
                map[name] = state.rawValue
            }
            if map.isEmpty {
                root.removeValue(forKey: "skillOverrides")
            } else {
                root["skillOverrides"] = map
            }
        }
        // Optimistic local update; the watcher will re-confirm on next file change.
        if state == .on {
            overrides.removeValue(forKey: name)
        } else {
            overrides[name] = state
        }
    }

    // MARK: - Private

    private func writeSettingsChange(_ mutate: (inout [String: Any]) -> Void) throws {
        var root: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: settingsURL.path) {
            let data = try Data(contentsOf: settingsURL)
            if let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                root = parsed
            } else {
                throw NSError(
                    domain: "SkillOverridesStore",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "settings.json is not a JSON object"]
                )
            }
        }
        mutate(&root)
        let parent = settingsURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parent.path) {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        }
        let out = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .withoutEscapingSlashes]
        )
        try out.write(to: settingsURL, options: .atomic)
    }

    private func startWatching() {
        watcher = nil
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return }
        watcher = DirectoryWatcher(url: settingsURL) { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
    }
}
