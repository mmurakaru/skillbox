import Foundation

/// Stash schema:
/// `{ "<settings.json absolute path>": { "VAR_NAME": "value", ... }, ... }`
typealias EnvVarStash = [String: [String: String]]

enum EnvVarScanner {
    /// Reads one settings.json + the disabled entries for that file from the stash.
    /// Yields `.enabled` rows from settings.json `env` first, then `.disabled` rows
    /// from the stash for keys that aren't already enabled (settings.json wins).
    static func scan(
        settingsURL: URL,
        scope: EnvScope,
        stashEntries: [String: String]
    ) -> [EnvVar] {
        let modifiedAt = (try? settingsURL.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? Date()

        var enabled: [EnvVar] = []
        var enabledKeys: Set<String> = []

        if let data = try? Data(contentsOf: settingsURL),
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let envMap = root["env"] as? [String: Any] {
            for (key, anyValue) in envMap {
                guard let value = stringify(anyValue) else { continue }
                enabled.append(
                    EnvVar(
                        key: key,
                        value: value,
                        state: .enabled,
                        scope: scope,
                        fileURL: settingsURL,
                        modifiedAt: modifiedAt
                    )
                )
                enabledKeys.insert(key)
            }
        }

        let disabled: [EnvVar] = stashEntries.compactMap { (key, value) in
            guard !enabledKeys.contains(key) else { return nil }
            return EnvVar(
                key: key,
                value: value,
                state: .disabled,
                scope: scope,
                fileURL: settingsURL,
                modifiedAt: modifiedAt
            )
        }

        return enabled + disabled
    }

    /// Loads the stash file. Returns empty if missing or malformed.
    static func loadStash(stashURL: URL) -> EnvVarStash {
        guard let data = try? Data(contentsOf: stashURL),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        var stash: EnvVarStash = [:]
        for (path, anyValue) in parsed {
            guard let entries = anyValue as? [String: Any] else { continue }
            var typed: [String: String] = [:]
            for (k, v) in entries {
                if let s = stringify(v) {
                    typed[k] = s
                }
            }
            if !typed.isEmpty {
                stash[path] = typed
            }
        }
        return stash
    }

    /// settings.json `env` values are documented as strings, but Claude Code
    /// itself coerces booleans/numbers to strings, so accept those defensively.
    private static func stringify(_ any: Any) -> String? {
        if let s = any as? String { return s }
        if let n = any as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() {
                return n.boolValue ? "true" : "false"
            }
            return n.stringValue
        }
        return nil
    }
}
