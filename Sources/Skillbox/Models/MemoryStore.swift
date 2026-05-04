import Foundation
import Observation

/// Aggregated metadata for a single Claude project that owns memory entries.
struct ProjectSummary: Identifiable, Hashable {
    let folderURL: URL
    let displayName: String
    let fullPath: String
    let count: Int
    let modifiedAt: Date

    var id: String { folderURL.path }
}

/// The store the Memory tab observes. Wraps a `FileBackedItemStore<Memory>`
/// for the file-watching plumbing and adds the project picker logic
/// (selectedProjectPath, availableProjects, project-aware filtering)
/// that the memory tab needs but the skills tab does not.
@MainActor
@Observable
final class MemoryStore {
    /// The list-of-files plumbing — the same one the Skills tab uses.
    let backing: FileBackedItemStore<Memory>

    /// Path of the project currently filtering the list, or nil for "all projects".
    var selectedProjectPath: String?

    init() {
        self.backing = FileBackedItemStore<Memory>(
            scan: { try MemoryScanner.scan(rootURL: $0) },
            matchesQuery: Self.matches,
            sort: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        )
    }

    init(seedMemories: [Memory]) {
        self.backing = FileBackedItemStore<Memory>(
            scan: { _ in seedMemories },
            matchesQuery: Self.matches,
            sort: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        )
        backing._seedForTesting(seedMemories)
    }

    // MARK: - Pass-through to backing store

    var memories: [Memory] { backing.items }
    var lastError: String? { backing.lastError }
    var searchQuery: String {
        get { backing.searchQuery }
        set { backing.searchQuery = newValue }
    }

    func configure(rootPath: String) { backing.configure(rootPath: rootPath) }
    func rescan() {
        backing.rescan()
        ensureValidSelection()
    }
    func remove(_ memory: Memory) { backing.remove(memory) }

    // MARK: - Project-aware view

    /// Distinct projects among the loaded memory entries, with per-project counts.
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

    /// Memory entries after the project picker and search query are applied.
    /// "All projects" is represented by `selectedProjectPath == nil` or empty string.
    var filteredMemories: [Memory] {
        let scoped = memories.filter { mem in
            guard let selected = selectedProjectPath, !selected.isEmpty else { return true }
            return mem.projectFolderURL.path == selected
        }
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return scoped }
        return scoped.filter { Self.matches($0, query) }
    }

    // MARK: - Private

    private static func matches(_ memory: Memory, _ query: String) -> Bool {
        memory.name.localizedCaseInsensitiveContains(query) ||
        memory.description.localizedCaseInsensitiveContains(query) ||
        memory.projectDisplayName.localizedCaseInsensitiveContains(query)
    }

    private func ensureValidSelection() {
        guard let selected = selectedProjectPath, !selected.isEmpty else { return }
        if !availableProjects.contains(where: { $0.folderURL.path == selected }) {
            selectedProjectPath = nil
        }
    }
}
