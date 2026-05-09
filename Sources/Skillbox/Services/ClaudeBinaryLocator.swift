import Foundation

enum ClaudeBinaryLocator {
    /// Resolve the path to the `claude` CLI binary.
    /// 1. If the user set `claudeCommand` in settings (an absolute path that exists), use it.
    /// 2. Otherwise search `$PATH` plus a handful of well-known fallback dirs.
    static func resolve(override: String?) -> Result {
        let trimmed = override?.trimmingCharacters(in: .whitespaces) ?? ""
        if !trimmed.isEmpty {
            if FileManager.default.isExecutableFile(atPath: trimmed) {
                return .resolved(trimmed)
            }
            return .overrideMissing(trimmed)
        }

        let dirs = pathDirs()
        let fm = FileManager.default
        for dir in dirs {
            let candidate = "\(dir)/claude"
            if fm.isExecutableFile(atPath: candidate) {
                return .resolved(candidate)
            }
        }
        return .notFoundOnPath(searched: dirs)
    }

    enum Result {
        case resolved(String)
        case overrideMissing(String)
        case notFoundOnPath(searched: [String])
    }

    static func pathDirs() -> [String] {
        let env = ProcessInfo.processInfo.environment["PATH"] ?? ""
        var dirs = env.split(separator: ":").map(String.init)
        let extras = [
            "/usr/local/bin",
            "/opt/homebrew/bin",
            "/usr/bin",
            "\(NSHomeDirectory())/.local/bin",
            "/opt/local/bin",
        ]
        for e in extras where !dirs.contains(e) { dirs.append(e) }
        return dirs
    }
}
