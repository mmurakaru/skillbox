import Foundation

struct DetectedEditor: Hashable {
    let displayName: String
    let command: String
    let path: String
}

enum EditorDetector {
    static let knownEditors: [(displayName: String, command: String)] = [
        ("Visual Studio Code", "code"),
        ("Cursor", "cursor"),
        ("Zed", "zed"),
        ("Sublime Text", "subl"),
        ("Nova", "nova"),
        ("BBEdit", "bbedit"),
        ("TextMate", "mate"),
    ]

    static func detect() -> [DetectedEditor] {
        let searchPaths = pathDirs()
        var found: [DetectedEditor] = []
        for entry in knownEditors {
            if let resolved = resolve(command: entry.command, in: searchPaths) {
                found.append(DetectedEditor(displayName: entry.displayName, command: entry.command, path: resolved))
            }
        }
        return found
    }

    private static func pathDirs() -> [String] {
        let env = ProcessInfo.processInfo.environment["PATH"] ?? ""
        var dirs = env.split(separator: ":").map(String.init)
        let extras = [
            "/usr/local/bin",
            "/opt/homebrew/bin",
            "\(NSHomeDirectory())/.local/bin",
            "/Applications/Visual Studio Code.app/Contents/Resources/app/bin",
            "/Applications/Cursor.app/Contents/Resources/app/bin",
        ]
        for e in extras where !dirs.contains(e) { dirs.append(e) }
        return dirs
    }

    private static func resolve(command: String, in dirs: [String]) -> String? {
        let fm = FileManager.default
        for dir in dirs {
            let candidate = "\(dir)/\(command)"
            if fm.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }
}
