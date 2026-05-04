import Testing
import Foundation
@testable import Skillbox

@MainActor
struct FileBackedItemStoreTests {
    private func makeSkill(name: String, description: String = "") -> Skill {
        Skill(
            name: name,
            description: description,
            folderURL: URL(fileURLWithPath: "/tmp/skills/\(name)"),
            modifiedAt: Date()
        )
    }

    @Test func searching_an_empty_query_returns_all_items() {
        let store = SkillStore(seedSkills: [
            makeSkill(name: "alpha"),
            makeSkill(name: "beta"),
        ])
        #expect(store.filteredItems.count == 2)
    }

    @Test func searching_filters_by_the_caller_provided_predicate() {
        let store = SkillStore(seedSkills: [
            makeSkill(name: "FrontendDesigner"),
            makeSkill(name: "BackendDesigner"),
        ])
        store.searchQuery = "frontend"
        #expect(store.filteredItems.map(\.name) == ["FrontendDesigner"])
    }

    @Test func searching_matches_descriptions_too_for_skills() {
        let store = SkillStore(seedSkills: [
            makeSkill(name: "alpha", description: "uses redis backend"),
            makeSkill(name: "beta", description: "uses postgres"),
        ])
        store.searchQuery = "redis"
        #expect(store.filteredItems.map(\.name) == ["alpha"])
    }

    @Test func searching_with_only_whitespace_is_treated_as_empty() {
        let store = SkillStore(seedSkills: [
            makeSkill(name: "alpha"),
            makeSkill(name: "beta"),
        ])
        store.searchQuery = "   "
        #expect(store.filteredItems.count == 2)
    }

    @Test func removing_an_item_drops_it_from_the_in_memory_list() {
        let target = makeSkill(name: "doomed")
        let store = SkillStore(seedSkills: [target, makeSkill(name: "survivor")])
        store.remove(target)
        #expect(store.items.map(\.name) == ["survivor"])
    }
}
