import Foundation

enum SkillCreator {
    enum CreateError: Error, LocalizedError {
        case invalidName
        case alreadyExists(URL)
        case writeFailed(Error)

        var errorDescription: String? {
            switch self {
            case .invalidName:
                return "Name must use lowercase letters, numbers, and hyphens"
            case .alreadyExists(let url):
                return "A skill named '\(url.lastPathComponent)' already exists"
            case .writeFailed(let err):
                return "Failed to create skill: \(err.localizedDescription)"
            }
        }
    }

    private static let allowedChars: Set<Character> = Set("abcdefghijklmnopqrstuvwxyz0123456789-")

    static func sanitize(_ raw: String) -> String {
        let lowered = raw.lowercased()
        let mapped = lowered.map { allowedChars.contains($0) ? $0 : "-" }
        var result = String(mapped)
        while result.contains("--") {
            result = result.replacingOccurrences(of: "--", with: "-")
        }
        return result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    static func isValidName(_ name: String) -> Bool {
        guard !name.isEmpty else { return false }
        return name.allSatisfy { allowedChars.contains($0) }
    }

    static func create(name: String, in rootPath: String) -> Result<URL, CreateError> {
        guard isValidName(name) else { return .failure(.invalidName) }

        let expanded = (rootPath as NSString).expandingTildeInPath
        let folder = URL(fileURLWithPath: expanded).appendingPathComponent(name)

        let fm = FileManager.default
        if fm.fileExists(atPath: folder.path) {
            return .failure(.alreadyExists(folder))
        }

        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            let skillFile = folder.appendingPathComponent("SKILL.md")
            let template = """
            ---
            name: \(name)
            description: TODO - describe what this skill does. Use when the user wants to ...
            ---

            # \(name)

            TODO: skill instructions here. See https://code.claude.com/docs/en/skills for guidance.
            """
            try template.write(to: skillFile, atomically: true, encoding: .utf8)
            return .success(folder)
        } catch {
            return .failure(.writeFailed(error))
        }
    }
}
