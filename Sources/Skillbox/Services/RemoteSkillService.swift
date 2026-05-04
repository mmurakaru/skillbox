import Foundation
import Observation

/// Install / update / check-for-updates lifecycle for remote-installed skills.
@MainActor
@Observable
final class RemoteSkillService {
    private let cli: SkillsCLIRunning
    private let registry: SkillRegistryFetching
    private let fileSystem: SkillsFileSystem

    init(
        cli: SkillsCLIRunning = SystemSkillsCLI(),
        registry: SkillRegistryFetching = GitHubSkillRegistry(),
        fileSystem: SkillsFileSystem = DefaultSkillsFileSystem()
    ) {
        self.cli = cli
        self.registry = registry
        self.fileSystem = fileSystem
    }

    struct InstalledSkill: Equatable {
        let folderURL: URL
        let name: String
    }

    enum ServiceError: LocalizedError {
        case installFailed(exitCode: Int32, output: String)
        case updateFailed(exitCode: Int32, output: String)
        case folderMissingAfterInstall(URL)
        case underlying(Error)

        var errorDescription: String? {
            switch self {
            case .installFailed(let code, let out):
                return "skills add failed (exit \(code)). \(out.trimmingCharacters(in: .whitespacesAndNewlines))"
            case .updateFailed(let code, let out):
                return "skills update failed (exit \(code)). \(out.trimmingCharacters(in: .whitespacesAndNewlines))"
            case .folderMissingAfterInstall(let url):
                return "Install reported success but \(url.path) does not exist."
            case .underlying(let err):
                return err.localizedDescription
            }
        }
    }

    // MARK: - Install

    func install(
        source: String,
        skill: String?,
        rootPath: String,
        stream: @escaping @MainActor (String) -> Void
    ) async throws -> InstalledSkill {
        let installedName = skill ?? Self.inferName(fromSource: source)
        let folderURL = URL(fileURLWithPath: (rootPath as NSString).expandingTildeInPath)
            .appendingPathComponent(installedName)

        let options = SkillsCLI.InstallOptions(source: source, skill: skill)

        let bridgedStream: @Sendable (String) -> Void = { chunk in
            Task { @MainActor in stream(chunk) }
        }

        let result: SkillsCLI.RunResult
        do {
            result = try await cli.install(options, stream: bridgedStream)
        } catch {
            throw ServiceError.underlying(error)
        }

        guard result.exitCode == 0 else {
            throw ServiceError.installFailed(exitCode: result.exitCode, output: result.combinedOutput)
        }

        guard fileSystem.folderExists(at: folderURL) else {
            throw ServiceError.folderMissingAfterInstall(folderURL)
        }

        let now = Date()
        var provenance = SkillProvenance(
            source: source,
            skill: installedName,
            ref: SkillRegistry.defaultBranch,
            sha: nil,
            installedAt: now,
            lastCheckedAt: now,
            latestKnownSHA: nil
        )

        if let coordinates = SkillSourceCoordinates.parse(provenance: provenance),
           let sha = try? await registry.latestSHA(
               repo: coordinates.repo,
               branch: coordinates.branch,
               path: coordinates.path
           ) {
            provenance.sha = sha
            provenance.latestKnownSHA = sha
        }

        do {
            try fileSystem.writeProvenance(provenance, to: folderURL)
        } catch {
            throw ServiceError.underlying(error)
        }

        return InstalledSkill(folderURL: folderURL, name: installedName)
    }

    // MARK: - Update

    /// CLI failure leaves the existing sidecar untouched.
    func update(
        _ skill: Skill,
        stream: @escaping @MainActor (String) -> Void
    ) async throws {
        guard let provenance = skill.provenance else { return }
        let target = provenance.skill ?? skill.name

        let bridgedStream: @Sendable (String) -> Void = { chunk in
            Task { @MainActor in stream(chunk) }
        }

        let result: SkillsCLI.RunResult
        do {
            result = try await cli.update(skillName: target, stream: bridgedStream)
        } catch {
            throw ServiceError.underlying(error)
        }

        guard result.exitCode == 0 else {
            throw ServiceError.updateFailed(exitCode: result.exitCode, output: result.combinedOutput)
        }

        await stampSHA(.acceptedUpgrade, provenance: provenance, folderURL: skill.folderURL)
    }

    // MARK: - Check for updates

    /// Skills whose source can't be parsed (or registry call fails) are silently skipped.
    func checkForUpdates(_ skills: [Skill]) async {
        for skill in skills {
            guard let provenance = skill.provenance else { continue }
            await stampSHA(.upstreamOnly, provenance: provenance, folderURL: skill.folderURL)
        }
    }

    // MARK: - Private

    private enum SHAStamp {
        /// Install / update — record the new SHA as both installed and upstream.
        case acceptedUpgrade
        /// Background poll — record only the upstream SHA.
        case upstreamOnly
    }

    private func stampSHA(_ stamp: SHAStamp, provenance: SkillProvenance, folderURL: URL) async {
        guard let coordinates = SkillSourceCoordinates.parse(provenance: provenance) else { return }
        guard let sha = try? await registry.latestSHA(
            repo: coordinates.repo,
            branch: coordinates.branch,
            path: coordinates.path
        ) else { return }

        var updated = provenance
        updated.latestKnownSHA = sha
        updated.lastCheckedAt = Date()
        switch stamp {
        case .acceptedUpgrade:
            updated.sha = sha
        case .upstreamOnly:
            if updated.sha == nil { updated.sha = sha }   // seed once on first check
        }
        try? fileSystem.writeProvenance(updated, to: folderURL)
    }

    static func inferName(fromSource source: String) -> String {
        let trimmed = source.trimmingCharacters(in: .whitespaces)
        let last = trimmed.split(separator: "/").last.map(String.init) ?? trimmed
        return last.replacingOccurrences(of: ".git", with: "")
    }
}
