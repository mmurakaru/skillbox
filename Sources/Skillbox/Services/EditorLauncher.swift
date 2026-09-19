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
        return openPath(pathToOpen, command: command)
    }

    @discardableResult
    static func openPath(_ path: String, command: String) -> Bool {
        let resolved = resolveCommand(command)
        if let resolved {
            return runProcess(executable: resolved, arguments: [path])
        }
        return openWithWorkspace(path: path)
    }

    @discardableResult
    static func openAsWorkspace(_ path: String, command: String) -> Bool {
        guard command == EditorDetector.preferredCommand,
              let resolved = resolveCommand(command) else {
            return openPath(path, command: command)
        }

        let targetURL = URL(fileURLWithPath: path)
        var isDirectory: ObjCBool = false
        let targetIsDirectory = FileManager.default.fileExists(
            atPath: targetURL.path,
            isDirectory: &isDirectory
        ) && isDirectory.boolValue
        let workspaceURL = targetIsDirectory ? targetURL : targetURL.deletingLastPathComponent()
        let arguments = targetIsDirectory ? ["."] : [".", targetURL.lastPathComponent]
        return runProcess(
            executable: resolved,
            arguments: arguments,
            currentDirectoryURL: workspaceURL,
            fallbackPath: path
        )
    }

    private static func resolveCommand(_ command: String) -> String? {
        if command.hasPrefix("/") {
            return FileManager.default.isExecutableFile(atPath: command) ? command : nil
        }
        return EditorDetector.detect().first(where: { $0.command == command })?.path
    }

    private static func runProcess(
        executable: String,
        arguments: [String],
        currentDirectoryURL: URL? = nil,
        fallbackPath: String? = nil
    ) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        task.currentDirectoryURL = currentDirectoryURL
        task.environment = ProcessInfo.processInfo.environment
        do {
            try task.run()
            return true
        } catch {
            return openWithWorkspace(path: fallbackPath ?? arguments.last ?? ".")
        }
    }

    private static func openWithWorkspace(path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        return NSWorkspace.shared.open(url)
    }
}
