import Foundation
import Yams

enum SkillScanner {
    static func scan(rootURL: URL) throws -> [Skill] {
        let fm = FileManager.default
        let children = try fm.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        return children.compactMap { childURL in
            guard (try? childURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
            let skillFile = childURL.appendingPathComponent("SKILL.md")
            guard fm.fileExists(atPath: skillFile.path) else { return nil }
            return parseSkill(folderURL: childURL, skillFileURL: skillFile)
        }
    }

    private static func parseSkill(folderURL: URL, skillFileURL: URL) -> Skill? {
        guard let data = try? Data(contentsOf: skillFileURL),
              let content = String(data: data, encoding: .utf8) else { return nil }

        guard let frontmatter = extractFrontmatter(from: content) else { return nil }

        guard let yaml = try? Yams.load(yaml: frontmatter) as? [String: Any] else { return nil }

        let name = (yaml["name"] as? String) ?? folderURL.lastPathComponent
        let description = (yaml["description"] as? String) ?? ""

        let modifiedAt = (try? skillFileURL.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? Date()

        let provenance = SkillProvenanceStore.read(from: folderURL)

        return Skill(
            name: name,
            description: description,
            folderURL: folderURL,
            modifiedAt: modifiedAt,
            provenance: provenance
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
}
