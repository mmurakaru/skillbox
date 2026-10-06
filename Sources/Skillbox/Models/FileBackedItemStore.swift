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
    private let acceptsWatchPath: (String) -> Bool

    private var watcher: DirectoryWatcher?
    private var rootPath: String = ""
    private var watchedPaths: [String] = []

    init(
        scan: @escaping (URL) throws -> [Item],
        matchesQuery: @escaping (Item, String) -> Bool,
        sort: @escaping (Item, Item) -> Bool,
        acceptsWatchPath: @escaping (String) -> Bool = { _ in true }
    ) {
        self.scan = scan
        self.matchesQuery = matchesQuery
        self.sort = sort
        self.acceptsWatchPath = acceptsWatchPath
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
        startWatching()
    }

    func remove(_ item: Item) {
        items.removeAll { $0.id == item.id }
    }

    private func startWatching() {
        let url = URL(fileURLWithPath: rootPath)
        // FSEvents does not follow child symlinks; watch their targets as well.
        let children = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isSymbolicLinkKey])) ?? []
        let targets = children.filter { (try? $0.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true }
            .map { $0.resolvingSymlinksInPath() }
        let urls = [url] + targets
        let paths = urls.map(\.path).sorted()
        guard paths != watchedPaths else { return }
        watchedPaths = paths
        watcher = DirectoryWatcher(urls: urls, acceptsPath: acceptsWatchPath) { [weak self] in
            Task { @MainActor in self?.rescan() }
        }
    }

    func _seedForTesting(_ items: [Item]) {
        self.items = items
    }
}
