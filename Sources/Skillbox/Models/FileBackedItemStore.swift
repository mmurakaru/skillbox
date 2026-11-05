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

    private let scan: @Sendable (URL) throws -> [Item]
    private let matchesQuery: (Item, String) -> Bool
    private let sort: @Sendable (Item, Item) -> Bool
    private let acceptsWatchPath: (String) -> Bool

    private var watcher: DirectoryWatcher?
    private var rootPath: String = ""
    private var watchedPaths: [String] = []
    @ObservationIgnored private var scanTask: Task<[Item], Error>?
    private var scanGeneration = 0

    init(
        scan: @escaping @Sendable (URL) throws -> [Item],
        matchesQuery: @escaping (Item, String) -> Bool,
        sort: @escaping @Sendable (Item, Item) -> Bool,
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

    @discardableResult
    func configure(rootPath: String) -> Task<Void, Never>? {
        let expanded = (rootPath as NSString).expandingTildeInPath

        if expanded == self.rootPath { return nil }

        self.rootPath = expanded
        return rescan()
    }

    @discardableResult
    func rescan() -> Task<Void, Never> {
        let url = URL(fileURLWithPath: rootPath)
        let scan = self.scan
        let sort = self.sort

        scanGeneration += 1
        let generation = scanGeneration

        scanTask?.cancel()
        startWatching()
        let task = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            return try scan(url).sorted(by: sort)
        }

        scanTask = task
        return Task {
            let result = await task.result

            guard generation == scanGeneration else { return }
            switch result {
            case .success(let found):
                items = found
                lastError = nil
            case .failure(is CancellationError):
                return
            case .failure(let error):
                lastError = "Failed to scan \(url.path): \(error.localizedDescription)"
            }
            // Reconcile edits made between the scan and adding a newly discovered symlink target.
            if startWatching() { rescan() }
        }
    }

    func remove(_ item: Item) {
        items.removeAll { $0.id == item.id }
    }

    @discardableResult
    private func startWatching() -> Bool {
        let url = URL(fileURLWithPath: rootPath)
        // FSEvents does not follow child symlinks; watch their targets as well.
        let children = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isSymbolicLinkKey])) ?? []
        let targets = children.filter { (try? $0.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true }
            .map { $0.resolvingSymlinksInPath() }
        let urls = [url] + targets
        let paths = urls.map(\.path).sorted()

        guard paths != watchedPaths else { return false }
        watchedPaths = paths
        watcher = DirectoryWatcher(urls: urls, acceptsPath: acceptsWatchPath) { [weak self] in
            Task { @MainActor in self?.rescan() }
        }

        return true
    }

    func _seedForTesting(_ items: [Item]) {
        self.items = items
    }
}
