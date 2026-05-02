import Foundation
import Yams

enum MemoryScanner {
    static func scan(rootURL: URL) throws -> [Memory] {
        let fm = FileManager.default
        let projects = try fm.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        var memories: [Memory] = []
        for projectURL in projects {
            guard (try? projectURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let memoryDir = projectURL.appendingPathComponent("memory")
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: memoryDir.path, isDirectory: &isDir), isDir.boolValue else { continue }

            let files = (try? fm.contentsOfDirectory(
                at: memoryDir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )) ?? []

            for fileURL in files {
                guard fileURL.pathExtension.lowercased() == "md" else { continue }
                guard fileURL.lastPathComponent != "MEMORY.md" else { continue }
                if let entry = parseMemory(fileURL: fileURL, projectFolderURL: projectURL) {
                    memories.append(entry)
                }
            }
        }
        return memories
    }

    private static func parseMemory(fileURL: URL, projectFolderURL: URL) -> Memory? {
        guard let data = try? Data(contentsOf: fileURL),
              let content = String(data: data, encoding: .utf8) else { return nil }

        let frontmatter = extractFrontmatter(from: content)
        let yaml = frontmatter.flatMap { try? Yams.load(yaml: $0) as? [String: Any] }

        let fallbackName = fileURL.deletingPathExtension().lastPathComponent
        let name = (yaml?["name"] as? String) ?? humanizeFilename(fallbackName)
        let description = (yaml?["description"] as? String) ?? ""
        let type = MemoryType.parse(yaml?["type"] as? String ?? typeFromFilename(fallbackName))

        let modifiedAt = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? Date()

        return Memory(
            name: name,
            description: description,
            type: type,
            fileURL: fileURL,
            projectFolderURL: projectFolderURL,
            modifiedAt: modifiedAt
        )
    }

    private static func extractFrontmatter(from content: String) -> String? {
        let lines = content.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return nil }
        var fmLines: [String] = []
        for line in lines.dropFirst() {
            if line.trimmingCharacters(in: .whitespaces) == "---" {
                return fmLines.joined(separator: "\n")
            }
            fmLines.append(line)
        }
        return nil
    }

    private static func typeFromFilename(_ name: String) -> String? {
        guard let underscore = name.firstIndex(of: "_") else { return nil }
        return String(name[..<underscore])
    }

    private static func humanizeFilename(_ name: String) -> String {
        name.replacingOccurrences(of: "_", with: " ")
    }
}
