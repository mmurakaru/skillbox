import Foundation
import Observation

/// Loads items from a configurable root directory and keeps the list in sync as
/// files change on disk. Specialised for skills and memory entries via the
/// `SkillStore`/`MemoryStore` typealiases below — adding a third item type is
/// a one-line conformance + a `convenience init`.
///
/// Why generic? Both concrete stores share the same shape: configure a path,
/// scan once, watch for changes, expose a filtered view of the results. The
/// generic captures the shape; callers inject the per-type pieces (how to
/// scan, how to match a search query, how to sort).
@MainActor
@Observable
final class FileBackedItemStore<Item: Identifiable & Sendable> {
    private(set) var items: [Item] = []
    private(set) var lastError: String?

    /// The user's current search query. Filtering is applied lazily via `filteredItems`.
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

    /// Items remaining after the current `searchQuery` is applied. Whitespace-only
    /// queries are treated as empty so a stray space doesn't blank the list.
    var filteredItems: [Item] {
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return items }
        return items.filter { matchesQuery($0, query) }
    }

    /// Point the store at a new root directory. Re-scans and starts watching for changes.
    /// No-op when the path hasn't actually changed.
    func configure(rootPath: String) {
        let expanded = (rootPath as NSString).expandingTildeInPath
        if expanded == self.rootPath { return }
        self.rootPath = expanded
        rescan()
        startWatching()
    }

    /// Force a re-read of the configured root.
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

    /// Drop a single item from the in-memory list (e.g. after the file is trashed).
    /// Filesystem deletion is the caller's responsibility; this store mirrors disk state.
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

    /// Inject seed items for tests. Bypasses scan/watch.
    func _seedForTesting(_ items: [Item]) {
        self.items = items
    }
}
