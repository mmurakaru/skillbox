import Foundation
import Testing

@testable import Skillbox

@MainActor
struct FileBackedItemStoreTests {
    @Test func scanningDoesNotBlockTheMainThread() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("skillbox-scan-\(UUID().uuidString)")

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SkillStore(
            scan: { _ in
                #expect(!Thread.isMainThread, "Skill scanning must not block startup or navigation")
                return []
            }, matchesQuery: { _, _ in true }, sort: { _, _ in false })

        await store.configure(rootPath: root.path)?.value
        #expect(store.lastError == nil)
    }

    @Test func slowOlderScanCannotOverwriteANewerRoot() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("skillbox-scan-order-\(UUID().uuidString)")
        let older = root.appendingPathComponent("older")
        let newer = root.appendingPathComponent("newer")

        try FileManager.default.createDirectory(at: older, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: newer, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let started = AsyncStream<Void>.makeStream()
        let release = DispatchSemaphore(value: 0)
        let store = SkillStore(
            scan: { url in
                if url.path == older.path {
                    started.continuation.yield(())
                    release.wait()
                }

                return [Skill(name: url.lastPathComponent, description: "", folderURL: url, modifiedAt: .distantPast)]
            }, matchesQuery: { _, _ in true }, sort: { _, _ in false })
        let oldScan = store.configure(rootPath: older.path)

        for await _ in started.stream { break }
        await store.configure(rootPath: newer.path)?.value
        release.signal()
        await oldScan?.value
        #expect(store.items.map(\.name) == ["newer"])
    }

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
