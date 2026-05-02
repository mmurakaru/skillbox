import Testing
import Foundation
@testable import Skillbox

@MainActor
struct SkillStoreTests {
    private func makeSkill(name: String, description: String = "") -> Skill {
        Skill(
            name: name,
            description: description,
            folderURL: URL(fileURLWithPath: "/tmp/skills/\(name)"),
            modifiedAt: Date()
        )
    }

    @Test func filtered_emptyQuery_returnsAll() {
        let store = SkillStore(seedSkills: [
            makeSkill(name: "alpha"),
            makeSkill(name: "beta"),
        ])
        #expect(store.filteredSkills.count == 2)
    }

    @Test func filtered_searchByName_caseInsensitive() {
        let store = SkillStore(seedSkills: [
            makeSkill(name: "FrontendDesigner"),
            makeSkill(name: "BackendDesigner"),
        ])
        store.searchQuery = "frontend"
        #expect(store.filteredSkills.map(\.name) == ["FrontendDesigner"])
    }

    @Test func filtered_searchByDescription_matches() {
        let store = SkillStore(seedSkills: [
            makeSkill(name: "alpha", description: "uses redis backend"),
            makeSkill(name: "beta", description: "uses postgres"),
        ])
        store.searchQuery = "redis"
        #expect(store.filteredSkills.map(\.name) == ["alpha"])
    }

    @Test func filtered_whitespaceOnly_treatedAsEmpty() {
        let store = SkillStore(seedSkills: [
            makeSkill(name: "alpha"),
            makeSkill(name: "beta"),
        ])
        store.searchQuery = "   "
        #expect(store.filteredSkills.count == 2)
    }

    @Test func remove_dropsMatchingSkill() {
        let target = makeSkill(name: "doomed")
        let store = SkillStore(seedSkills: [target, makeSkill(name: "survivor")])
        store.remove(target)
        #expect(store.skills.map(\.name) == ["survivor"])
    }
}
