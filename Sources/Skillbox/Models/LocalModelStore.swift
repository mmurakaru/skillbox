import Foundation
import Observation
import ModelInventory

/// Local AI model inventory behind the Models tab. Scans at launch and again when a watched model folder changes.
@MainActor
@Observable
final class LocalModelStore {
    private(set) var models: [LocalModel]
    private(set) var isScanning = false
    private(set) var duplicateGroups: [DuplicateModelGroup] = []
    private(set) var isDetectingDuplicates = false

    var searchQuery = ""

    private var configuration: LocalModelScanConfiguration?
    private var scanners: [any LocalModelScanner] = []
    private var watcher: DirectoryWatcher?
    private let duplicateDetector = DuplicateModelDetector()
    private let makeScanners: (LocalModelScanConfiguration) -> [any LocalModelScanner]
    // Bumped per scan so a slow, older scan or duplicate search cannot overwrite newer results.
    private var inventoryGeneration = 0

    init(
        makeScanners: @escaping (LocalModelScanConfiguration) -> [any LocalModelScanner] = { $0.makeScanners() },
        seedModels: [LocalModel] = []
    ) {
        self.makeScanners = makeScanners
        self.models = seedModels
    }

    var filteredModels: [LocalModel] {
        let query = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return models }
        return models.filter {
            $0.name.lowercased().contains(query) || $0.source.displayName.lowercased().contains(query)
        }
    }

    var totalBytes: Int64 {
        models.reduce(0) { $0 + $1.sizeBytes }
    }

    /// Space freed by keeping one copy of each duplicate group.
    var reclaimableBytes: Int64 {
        duplicateGroups.reduce(0) { $0 + $1.reclaimableBytes }
    }

    /// Applies scan settings, watches the scanned folders, and rescans. Repeating the same configuration does nothing.
    func configure(_ newConfiguration: LocalModelScanConfiguration) {
        guard newConfiguration != configuration else { return }
        configuration = newConfiguration
        scanners = makeScanners(newConfiguration)
        startWatching()
        rescan()
    }

    @discardableResult
    func rescan() -> Task<Void, Never> {
        inventoryGeneration += 1
        let generation = inventoryGeneration
        let scanners = self.scanners
        isScanning = true
        return Task {
            let found = await Task.detached(priority: .utility) {
                LocalModelInventory.aggregate(scanners)
            }.value
            guard generation == inventoryGeneration else { return }
            models = found
            duplicateGroups = []
            isScanning = false
        }
    }

    /// Hashes same-size files to find byte-identical copies. Runs only on request because it reads whole files.
    @discardableResult
    func findDuplicates() -> Task<Void, Never>? {
        guard !isDetectingDuplicates else { return nil }
        isDetectingDuplicates = true
        let generation = inventoryGeneration
        let snapshot = models
        return Task {
            let groups = await duplicateDetector.findDuplicates(in: snapshot)
            isDetectingDuplicates = false
            guard generation == inventoryGeneration else { return }
            duplicateGroups = groups
        }
    }

    /// Number of copies of this model; 1 when it is unique or duplicates were not searched yet.
    func copyCount(for model: LocalModel) -> Int {
        duplicateGroups.first { group in
            group.models.contains { $0.id == model.id }
        }?.models.count ?? 1
    }

    private func startWatching() {
        let roots = scanners.flatMap(\.watchRoots)
        watcher = roots.isEmpty ? nil : DirectoryWatcher(urls: roots) { [weak self] in
            Task { @MainActor in self?.rescan() }
        }
    }
}
