import Foundation
import Observation

struct ProjectSummary: Identifiable, Hashable {
    let folderURL: URL
    let displayName: String
    let fullPath: String
    let count: Int
    let modifiedAt: Date

    var id: String { folderURL.path }
}

@MainActor
@Observable
final class MemoryStore {
    private(set) var memories: [Memory] = []
    private(set) var lastError: String?

    var searchQuery: String = ""
    var selectedProjectPath: String?

    private var watcher: DirectoryWatcher?
    private var rootPath: String = ""

    init() {}

    init(seedMemories: [Memory]) {
        self.memories = seedMemories
    }

    var availableProjects: [ProjectSummary] {
        let groups = Dictionary(grouping: memories) { $0.projectFolderURL.path }
        return groups.map { (_, entries) in
            let first = entries[0]
            let mostRecent = entries.map(\.modifiedAt).max() ?? first.modifiedAt
            return ProjectSummary(
                folderURL: first.projectFolderURL,
                displayName: first.projectDisplayName,
                fullPath: first.projectFullPath,
                count: entries.count,
                modifiedAt: mostRecent
            )
        }
        .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    var filteredMemories: [Memory] {
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        let scoped = memories.filter { mem in
            guard let selected = selectedProjectPath, !selected.isEmpty else { return true }
            return mem.projectFolderURL.path == selected
        }
        guard !query.isEmpty else { return scoped }
        return scoped.filter { mem in
            mem.name.localizedCaseInsensitiveContains(query) ||
            mem.description.localizedCaseInsensitiveContains(query) ||
            mem.projectDisplayName.localizedCaseInsensitiveContains(query)
        }
    }

    func configure(rootPath: String) {
        let expanded = (rootPath as NSString).expandingTildeInPath
        if expanded == self.rootPath { return }
        self.rootPath = expanded
        rescan()
        startWatching()
    }

    func rescan() {
        let url = URL(fileURLWithPath: rootPath)
        do {
            memories = try MemoryScanner.scan(rootURL: url)
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            lastError = nil
            ensureValidSelection()
        } catch {
            memories = []
            lastError = "Failed to scan \(rootPath): \(error.localizedDescription)"
        }
    }

    func remove(_ memory: Memory) {
        memories.removeAll { $0.id == memory.id }
    }

    private func ensureValidSelection() {
        guard let selected = selectedProjectPath, !selected.isEmpty else { return }
        if !availableProjects.contains(where: { $0.folderURL.path == selected }) {
            selectedProjectPath = nil
        }
    }

    private func startWatching() {
        watcher = nil
        let url = URL(fileURLWithPath: rootPath)
        watcher = DirectoryWatcher(url: url) { [weak self] in
            Task { @MainActor in self?.rescan() }
        }
    }
}
