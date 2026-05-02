import Foundation
import AppKit

enum OpenTarget: String, CaseIterable, Identifiable {
    case folder
    case skillMd = "skill_md"

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .folder: "Skill folder"
        case .skillMd: "SKILL.md only"
        }
    }
}

enum EditorLauncher {
    @discardableResult
    static func open(skill: Skill, command: String, target: OpenTarget) -> Bool {
        let pathToOpen = target == .folder ? skill.folderURL.path : skill.skillFileURL.path
        let resolved = resolveCommand(command)

        if let resolved {
            return runProcess(executable: resolved, arg: pathToOpen)
        }
        return openWithWorkspace(path: pathToOpen)
    }

    private static func resolveCommand(_ command: String) -> String? {
        if command.hasPrefix("/") {
            return FileManager.default.isExecutableFile(atPath: command) ? command : nil
        }
        return EditorDetector.detect().first(where: { $0.command == command })?.path
    }

    private static func runProcess(executable: String, arg: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = [arg]
        task.environment = ProcessInfo.processInfo.environment
        do {
            try task.run()
            return true
        } catch {
            return openWithWorkspace(path: arg)
        }
    }

    private static func openWithWorkspace(path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        return NSWorkspace.shared.open(url)
    }
}
