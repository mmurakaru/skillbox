import Foundation

/// Production: wraps `SkillsCLI`. Tests: in-memory adapter.
protocol SkillsCLIRunning: Sendable {
    func install(
        _ options: SkillsCLI.InstallOptions,
        stream: @escaping @Sendable (String) -> Void
    ) async throws -> SkillsCLI.RunResult

    func update(
        skillName: String,
        stream: @escaping @Sendable (String) -> Void
    ) async throws -> SkillsCLI.RunResult
}

/// Production: wraps `SkillRegistry`. Tests: in-memory adapter with canned SHAs.
protocol SkillRegistryFetching: Sendable {
    func latestSHA(repo: String, branch: String, path: String) async throws -> String?
}

/// Production: wraps `SkillProvenanceStore`. Tests: in-memory dictionary.
protocol SkillsFileSystem: Sendable {
    func readProvenance(at folderURL: URL) -> SkillProvenance?
    func writeProvenance(_ provenance: SkillProvenance, to folderURL: URL) throws
    func folderExists(at url: URL) -> Bool
}

// MARK: - Production adapters

struct SystemSkillsCLI: SkillsCLIRunning {
    func install(
        _ options: SkillsCLI.InstallOptions,
        stream: @escaping @Sendable (String) -> Void
    ) async throws -> SkillsCLI.RunResult {
        try await SkillsCLI.install(options, stream: stream)
    }

    func update(
        skillName: String,
        stream: @escaping @Sendable (String) -> Void
    ) async throws -> SkillsCLI.RunResult {
        try await SkillsCLI.update(skillName: skillName, stream: stream)
    }
}

struct GitHubSkillRegistry: SkillRegistryFetching {
    func latestSHA(repo: String, branch: String, path: String) async throws -> String? {
        try await SkillRegistry.latestSHA(repo: repo, branch: branch, path: path)
    }
}

struct DefaultSkillsFileSystem: SkillsFileSystem {
    func readProvenance(at folderURL: URL) -> SkillProvenance? {
        SkillProvenanceStore.read(from: folderURL)
    }

    func writeProvenance(_ provenance: SkillProvenance, to folderURL: URL) throws {
        try SkillProvenanceStore.write(provenance, to: folderURL)
    }

    func folderExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }
}
