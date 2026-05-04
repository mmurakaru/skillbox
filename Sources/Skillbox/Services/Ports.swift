import Foundation

/// Runs the `skills` CLI on behalf of `RemoteSkillService`.
///
/// Production wraps `SkillsCLI` (subprocess via `npx skills`).
/// Tests substitute an in-memory adapter that records calls.
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

/// Reads metadata from a remote skills registry (currently GitHub).
///
/// Production wraps `SkillRegistry` (HTTPS to api.github.com).
/// Tests substitute an in-memory adapter that returns canned SHAs.
protocol SkillRegistryFetching: Sendable {
    func latestSHA(repo: String, branch: String, path: String) async throws -> String?
}

/// Persists the per-skill `.skillbox.json` provenance sidecar.
///
/// Production wraps `SkillProvenanceStore` (filesystem).
/// Tests substitute an in-memory dictionary keyed by folder URL.
protocol SkillsFileSystem: Sendable {
    func readProvenance(at folderURL: URL) -> SkillProvenance?
    func writeProvenance(_ provenance: SkillProvenance, to folderURL: URL) throws
    func folderExists(at url: URL) -> Bool
}

// MARK: - Production adapters

/// Production CLI adapter: shells out via `SkillsCLI` (npx skills).
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

/// Production registry adapter: fetches from `SkillRegistry` (GitHub Contents/Commits API).
struct GitHubSkillRegistry: SkillRegistryFetching {
    func latestSHA(repo: String, branch: String, path: String) async throws -> String? {
        try await SkillRegistry.latestSHA(repo: repo, branch: branch, path: path)
    }
}

/// Production filesystem adapter: reads/writes `.skillbox.json` via `SkillProvenanceStore`.
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
