import Testing
import Foundation
@testable import Skillbox

@MainActor
struct MemoryStoreTests {
    private func makeMemory(
        name: String,
        description: String = "",
        type: MemoryType = .other,
        projectFolderName: String,
        fileName: String? = nil
    ) -> Memory {
        let projectFolder = URL(fileURLWithPath: "/tmp/projects/\(projectFolderName)")
        let fileURL = projectFolder
            .appendingPathComponent("memory")
            .appendingPathComponent(fileName ?? "\(name).md")
        return Memory(
            name: name,
            description: description,
            type: type,
            fileURL: fileURL,
            projectFolderURL: projectFolder,
            modifiedAt: Date()
        )
    }

    // MARK: - filteredMemories

    @Test func filtered_emptyQueryNoSelection_returnsAll() {
        let store = MemoryStore(seedMemories: [
            makeMemory(name: "alpha", projectFolderName: "-Users-alice-projectA"),
            makeMemory(name: "beta", projectFolderName: "-Users-alice-projectB"),
        ])
        #expect(store.filteredMemories.count == 2)
    }

    @Test func filtered_projectSelected_returnsOnlyThatProject() {
        let store = MemoryStore(seedMemories: [
            makeMemory(name: "alpha", projectFolderName: "-Users-alice-projectA"),
            makeMemory(name: "beta", projectFolderName: "-Users-alice-projectB"),
            makeMemory(name: "gamma", projectFolderName: "-Users-alice-projectA"),
        ])
        store.selectedProjectPath = "/tmp/projects/-Users-alice-projectA"
        let names = store.filteredMemories.map(\.name).sorted()
        #expect(names == ["alpha", "gamma"])
    }

    @Test func filtered_searchByName_matchesCaseInsensitive() {
        let store = MemoryStore(seedMemories: [
            makeMemory(name: "Use pnpm", projectFolderName: "-Users-alice-a"),
            makeMemory(name: "Avoid npm", projectFolderName: "-Users-alice-a"),
        ])
        store.searchQuery = "PNPM"
        #expect(store.filteredMemories.map(\.name) == ["Use pnpm"])
    }

    @Test func filtered_searchByDescription_matches() {
        let store = MemoryStore(seedMemories: [
            makeMemory(name: "alpha", description: "uses redis backend", projectFolderName: "-Users-alice-a"),
            makeMemory(name: "beta", description: "uses postgres", projectFolderName: "-Users-alice-a"),
        ])
        store.searchQuery = "redis"
        #expect(store.filteredMemories.map(\.name) == ["alpha"])
    }

    @Test func filtered_searchByProjectName_matchesAcrossProjects() {
        let store = MemoryStore(seedMemories: [
            makeMemory(name: "alpha", projectFolderName: "-Users-alice-widget"),
            makeMemory(name: "beta", projectFolderName: "-Users-alice-gizmo"),
        ])
        store.searchQuery = "widget"
        #expect(store.filteredMemories.map(\.name) == ["alpha"])
    }

    @Test func filtered_combinesProjectAndQuery() {
        let store = MemoryStore(seedMemories: [
            makeMemory(name: "alpha redis", projectFolderName: "-Users-alice-projectA"),
            makeMemory(name: "beta redis", projectFolderName: "-Users-alice-projectB"),
            makeMemory(name: "gamma postgres", projectFolderName: "-Users-alice-projectA"),
        ])
        store.selectedProjectPath = "/tmp/projects/-Users-alice-projectA"
        store.searchQuery = "redis"
        #expect(store.filteredMemories.map(\.name) == ["alpha redis"])
    }

    @Test func filtered_emptySelectedProjectPath_treatedAsAllProjects() {
        let store = MemoryStore(seedMemories: [
            makeMemory(name: "alpha", projectFolderName: "-Users-alice-a"),
            makeMemory(name: "beta", projectFolderName: "-Users-alice-b"),
        ])
        store.selectedProjectPath = ""
        #expect(store.filteredMemories.count == 2)
    }

    // MARK: - availableProjects

    @Test func availableProjects_groupsByProjectAndCounts() {
        let store = MemoryStore(seedMemories: [
            makeMemory(name: "a1", projectFolderName: "-Users-alice-projectA"),
            makeMemory(name: "a2", projectFolderName: "-Users-alice-projectA"),
            makeMemory(name: "b1", projectFolderName: "-Users-alice-projectB"),
        ])
        let projects = store.availableProjects
        #expect(projects.count == 2)
        let counts = Dictionary(uniqueKeysWithValues: projects.map { ($0.folderURL.lastPathComponent, $0.count) })
        #expect(counts["-Users-alice-projectA"] == 2)
        #expect(counts["-Users-alice-projectB"] == 1)
    }

    @Test func availableProjects_sortedByDisplayName() {
        let store = MemoryStore(seedMemories: [
            makeMemory(name: "x", projectFolderName: "-Users-alice-zeta"),
            makeMemory(name: "y", projectFolderName: "-Users-alice-alpha"),
            makeMemory(name: "z", projectFolderName: "-Users-alice-mu"),
        ])
        let names = store.availableProjects.map(\.displayName)
        #expect(names == names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
    }

    // MARK: - remove

    @Test func remove_dropsMatchingEntry() {
        let target = makeMemory(name: "doomed", projectFolderName: "-Users-alice-a")
        let store = MemoryStore(seedMemories: [
            target,
            makeMemory(name: "survivor", projectFolderName: "-Users-alice-a"),
        ])
        store.remove(target)
        #expect(store.memories.map(\.name) == ["survivor"])
    }
}
