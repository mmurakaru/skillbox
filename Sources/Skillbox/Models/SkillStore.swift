import Foundation

/// The store the Skills tab observes. A specialisation of `FileBackedItemStore`
/// that knows how to scan `~/.claude/skills/` and search by name + description.
typealias SkillStore = FileBackedItemStore<Skill>

extension FileBackedItemStore where Item == Skill {
    convenience init() {
        self.init(
            scan: { try SkillScanner.scan(rootURL: $0) },
            matchesQuery: { skill, query in
                skill.name.localizedCaseInsensitiveContains(query) ||
                skill.description.localizedCaseInsensitiveContains(query)
            },
            sort: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        )
    }

    convenience init(seedSkills: [Skill]) {
        self.init()
        _seedForTesting(seedSkills)
    }
}
