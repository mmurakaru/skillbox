import Foundation

struct Skill: Identifiable, Hashable {
    let id: String
    let name: String
    let description: String
    let folderURL: URL
    let skillFileURL: URL
    let modifiedAt: Date

    init(name: String, description: String, folderURL: URL, modifiedAt: Date) {
        self.id = folderURL.path
        self.name = name
        self.description = description
        self.folderURL = folderURL
        self.skillFileURL = folderURL.appendingPathComponent("SKILL.md")
        self.modifiedAt = modifiedAt
    }
}
