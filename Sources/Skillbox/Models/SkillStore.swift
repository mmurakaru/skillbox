import Foundation

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
