import Foundation
import Observation

/// Loads items from a directory, watches for changes, exposes a search-filtered view.
/// Callers inject the per-type scan/match/sort closures (see `SkillStore`, `MemoryStore`).
@MainActor
@Observable
final class FileBackedItemStore<Item: Identifiable & Sendable> {
    private(set) var items: [Item] = []
    private(set) var lastError: String?

    var searchQuery: String = ""

    private let scan: (URL) throws -> [Item]
    private let matchesQuery: (Item, String) -> Bool
    private let sort: (Item, Item) -> Bool

    private var watcher: DirectoryWatcher?
    private var rootPath: String = ""

    init(
        scan: @escaping (URL) throws -> [Item],
        matchesQuery: @escaping (Item, String) -> Bool,
        sort: @escaping (Item, Item) -> Bool
    ) {
        self.scan = scan
        self.matchesQuery = matchesQuery
        self.sort = sort
    }

    var filteredItems: [Item] {
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return items }
        return items.filter { matchesQuery($0, query) }
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
            items = try scan(url).sorted(by: sort)
            lastError = nil
        } catch {
            items = []
            lastError = "Failed to scan \(rootPath): \(error.localizedDescription)"
        }
    }

    func remove(_ item: Item) {
        items.removeAll { $0.id == item.id }
    }

    private func startWatching() {
        watcher = nil
        let url = URL(fileURLWithPath: rootPath)
        watcher = DirectoryWatcher(url: url) { [weak self] in
            Task { @MainActor in self?.rescan() }
        }
    }

    func _seedForTesting(_ items: [Item]) {
        self.items = items
    }
}
