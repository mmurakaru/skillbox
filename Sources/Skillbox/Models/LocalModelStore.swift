import Foundation
import ModelInventory
import Observation

/// Local AI model inventory behind the Models tab. Scans at launch and again when a watched model folder changes.
@MainActor
@Observable
final class LocalModelStore {
    private(set) var models: [LocalModel]
    private(set) var isScanning = false
    private(set) var duplicateGroups: [DuplicateModelGroup] = []
    private(set) var isDetectingDuplicates = false
    private(set) var runtimeStates: [String: ModelRuntimeState] = [:]

    var searchQuery = ""

    private var configuration: LocalModelScanConfiguration?
    private var scanners: [any LocalModelScanner] = []
    private var watcher: DirectoryWatcher?
    private var missingWatchRoots: [URL] = []
    private var rootAppearanceCheck: Task<Void, Never>?
    private var scanTask: Task<[LocalModel], Never>?
    private static let watcherEventQueue = DispatchQueue(label: "skillbox.local-models.watcher", qos: .utility)
    private static let rootAppearanceCheckInterval: Duration = .seconds(300)
    private let duplicateDetector = DuplicateModelDetector()
    private let runtimeMonitor: any ModelRuntimeMonitoring
    private let moveItemToTrash: (URL) throws -> Void
    private let makeScanners: (LocalModelScanConfiguration) -> [any LocalModelScanner]
    // Bumped per scan so a slow, older scan cannot overwrite newer results.
    private var inventoryGeneration = 0

    init(
        makeScanners: @escaping (LocalModelScanConfiguration) -> [any LocalModelScanner] = { $0.makeScanners() },
        runtimeMonitor: any ModelRuntimeMonitoring = ModelRuntimeMonitor(),
        moveItemToTrash: @escaping (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) },
        seedModels: [LocalModel] = []
    ) {
        self.makeScanners = makeScanners
        self.runtimeMonitor = runtimeMonitor
        self.moveItemToTrash = moveItemToTrash
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
        models.totalStorageBytes
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
        scanTask?.cancel()
        let scan = Task.detached(priority: .utility) {
            LocalModelInventory.aggregate(scanners)
        }

        scanTask = scan

        return Task {
            let found = await scan.value

            guard generation == inventoryGeneration else { return }
            models = found
            duplicateGroups = Self.groups(duplicateGroups, keepingMembersUnchangedIn: found)
            isScanning = false
        }
    }

    /// Hashes same-size files to find byte-identical copies. Runs only on request because it reads whole files.
    @discardableResult
    func findDuplicates() -> Task<Void, Never>? {
        guard !isDetectingDuplicates else { return nil }
        isDetectingDuplicates = true
        let snapshot = models

        return Task {
            let groups = await duplicateDetector.findDuplicates(in: snapshot)

            isDetectingDuplicates = false
            duplicateGroups = Self.groups(groups, keepingMembersUnchangedIn: models)
        }
    }

    /// Keeps hash results for files that did not change, so a slow duplicate search survives unrelated folder events.
    private static func groups(_ groups: [DuplicateModelGroup], keepingMembersUnchangedIn models: [LocalModel]) -> [DuplicateModelGroup] {
        let currentModels = Dictionary(models.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        return groups.compactMap { group in
            let unchangedMembers = group.models.compactMap { member -> LocalModel? in
                guard let current = currentModels[member.id],
                    current.sizeBytes == member.sizeBytes,
                    current.modifiedAt == member.modifiedAt
                else { return nil }

                return current
            }

            return unchangedMembers.count > 1 ? DuplicateModelGroup(id: group.id, models: unchangedMembers) : nil
        }
    }

    /// Number of copies of this model; 1 when it is unique or duplicates were not searched yet.
    func copyCount(for model: LocalModel) -> Int {
        duplicateGroups.first { group in
            group.models.contains { $0.id == model.id }
        }?.models.count ?? 1
    }

    /// Reads which models are loaded in memory. Called only while the Models tab is visible.
    func refreshRuntimeStates() async {
        guard !models.isEmpty else {
            runtimeStates = [:]

            return
        }
        runtimeStates = await runtimeMonitor.runtimeStates(for: models)
    }

    func runtimeState(for model: LocalModel) -> ModelRuntimeState? {
        runtimeStates[model.id]
    }

    /// Unloads a cleanly stoppable model, then refreshes runtime state.
    func stop(_ model: LocalModel) async {
        guard let target = runtimeStates[model.id]?.stopTarget else { return }
        await runtimeMonitor.stop(target, weightFileURLs: model.weightFileURLs)
        await refreshRuntimeStates()
    }

    /// Moves a model to the Trash and drops it from the inventory and its duplicate group.
    func moveToTrash(_ model: LocalModel) throws {
        guard LocalModelTrashPolicy.canMoveToTrash(model) else { throw LocalModelTrashError.managedByOllama(model.name) }
        guard runtimeStates[model.id] == nil else { throw LocalModelTrashError.loadedInMemory(model.name) }
        try moveItemToTrash(model.path)
        models.removeAll { $0.id == model.id }
        runtimeStates[model.id] = nil
        duplicateGroups =
            duplicateGroups
            .map { DuplicateModelGroup(id: $0.id, models: $0.models.filter { $0.id != model.id }) }
            .filter { $0.models.count > 1 }
    }

    /// Starts watching model folders created since the last check; returns true when it rescanned.
    @discardableResult
    func watchModelFoldersCreatedSinceLastCheck() -> Bool {
        guard missingWatchRoots.contains(where: { FileManager.default.fileExists(atPath: $0.path) }) else { return false }
        startWatching()
        rescan()

        return true
    }

    private func startWatching() {
        let roots = scanners.flatMap(\.watchRoots)

        missingWatchRoots = roots.filter { !FileManager.default.fileExists(atPath: $0.path) }
        watcher =
            roots.isEmpty
            ? nil
            : DirectoryWatcher(
                urls: roots,
                watchesMissingPathsThroughAncestors: false,
                eventQueue: Self.watcherEventQueue
            ) { [weak self] in
                Task { @MainActor in self?.rescan() }
            }
        scheduleRootAppearanceCheck()
    }

    /// Missing folders are not watched through a broad ancestor such as the home folder, so a slow timer re-checks them.
    private func scheduleRootAppearanceCheck() {
        rootAppearanceCheck?.cancel()
        guard !missingWatchRoots.isEmpty else { return }
        rootAppearanceCheck = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.rootAppearanceCheckInterval)
                guard !Task.isCancelled, let self else { return }

                if self.watchModelFoldersCreatedSinceLastCheck() { return }
            }
        }
    }
}

/// Why a local model could not be moved to the Trash.
enum LocalModelTrashError: LocalizedError, Equatable {
    case managedByOllama(String)
    case loadedInMemory(String)

    var errorDescription: String? {
        switch self {
        case .managedByOllama(let name): "Ollama manages the files of \(name). Remove it with `ollama rm \(name)`."
        case .loadedInMemory(let name): "\(name) is loaded in memory. Unload it before moving it to the Trash."
        }
    }
}
