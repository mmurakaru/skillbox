import Foundation

enum ClaudeSettingsWatchRoots {
    static func watchURLs(claudeHomePath: String) -> [URL] {
        let home = URL(fileURLWithPath: claudeHomePath)
        let projects = (try? FileManager.default.contentsOfDirectory(
            at: home.appendingPathComponent("projects"),
            includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        )) ?? []
        let projectSettings = projects.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }.map {
            URL(fileURLWithPath: Memory.decodeProjectPath($0.lastPathComponent).full).appendingPathComponent(".claude")
        }
        return [home] + projectSettings
    }

    // New project directories matter; conversation log writes do not.
    static func acceptsWatchPath(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        return ["settings.json", "settings.local.json", "skillbox-env-stash.json"].contains(url.lastPathComponent) || url.pathExtension.isEmpty
    }
}
