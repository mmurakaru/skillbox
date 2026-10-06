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
        var additionalNames: [String] = []
        var names: [String] { [name] + additionalNames }
    }

    enum ServiceError: LocalizedError {
        case installFailed(exitCode: Int32, output: String)
        case updateFailed(exitCode: Int32, output: String)
        case folderMissingAfterInstall(URL)
        case underlying(Error)

        var errorDescription: String? {
            switch self {
            case .installFailed(let code, let out):
                return SkillInstallOutput.failureMessage(output: out, exitCode: code)
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
        rootPath: String,
        claudeMountPath: String? = nil,
        stream: @escaping @MainActor (String) -> Void
    ) async throws -> InstalledSkill {
        let installedName = Self.inferName(fromSource: source)
        let rootURL = URL(fileURLWithPath: (rootPath as NSString).expandingTildeInPath)
        let mountRootURL = claudeMountPath.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }

        let options = SkillsCLI.InstallOptions(source: source)

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

        let reportedNames = SkillInstallOutput.installedNames(output: result.combinedOutput)
        let names = reportedNames.isEmpty ? [installedName] : reportedNames
        let sourceCoordinates = SkillSourceCoordinates.parse(provenance: SkillProvenance(source: source))
        let paths: [String]
        if let sourceCoordinates {
            paths = (try? await registry.skillPaths(repo: sourceCoordinates.repo, branch: sourceCoordinates.branch)) ?? []
        } else { paths = [] }
        var installedFolders: [URL] = []
        for name in names {
            let folder = try reconcileInstalledFolder(
                installedName: name,
                sourceRootURL: rootURL,
                mountedFolderURL: mountRootURL?.appendingPathComponent(name)
            )
            let now = Date()
            var provenance = SkillProvenance(
                source: source, skill: name, ref: SkillRegistry.defaultBranch,
                installedAt: now, lastCheckedAt: now,
                remotePath: Self.resolveRemotePath(name: name, source: source, coordinates: sourceCoordinates, paths: paths)
            )
            if let coordinates = SkillSourceCoordinates.parse(provenance: provenance),
               let sha = try? await registry.latestSHA(repo: coordinates.repo, branch: coordinates.branch, path: coordinates.path) {
                provenance.sha = sha
                provenance.latestKnownSHA = sha
            }
            do {
                try fileSystem.writeProvenance(provenance, to: folder)
                if let mountRootURL {
                    try reconcileClaudeMount(sourceURL: folder, mountRootURL: mountRootURL)
                }
            } catch { throw ServiceError.underlying(error) }
            installedFolders.append(folder)
        }
        return InstalledSkill(folderURL: installedFolders[0], name: names[0], additionalNames: Array(names.dropFirst()))
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

    private func reconcileInstalledFolder(
        installedName: String,
        sourceRootURL: URL,
        mountedFolderURL: URL?
    ) throws -> URL {
        let fm = FileManager.default
        let folderURL = sourceRootURL.appendingPathComponent(installedName)

        // A fresh Claude copy wins over an older custom canonical folder; keep the old files as a backup.
        if let mountedFolderURL, mountedFolderURL != folderURL,
           !SkillMountSync.isSymlink(mountedFolderURL), fm.fileExists(atPath: mountedFolderURL.path) {
            try fm.createDirectory(at: sourceRootURL, withIntermediateDirectories: true)
            var backup: URL?
            if fm.fileExists(atPath: folderURL.path) || SkillMountSync.isSymlink(folderURL) {
                let destination = sourceRootURL.appendingPathComponent(".skillbox-backups/\(UUID().uuidString)/\(installedName)")
                try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.moveItem(at: folderURL, to: destination)
                backup = destination
            }
            do { try fm.moveItem(at: mountedFolderURL, to: folderURL) }
            catch {
                if let backup { try? fm.moveItem(at: backup, to: folderURL) }
                throw error
            }
            return folderURL
        }

        if fileSystem.folderExists(at: folderURL) {
            return folderURL
        }

        guard let mountedFolderURL else {
            throw ServiceError.folderMissingAfterInstall(folderURL)
        }

        guard fm.fileExists(atPath: mountedFolderURL.path) else {
            throw ServiceError.folderMissingAfterInstall(folderURL)
        }

        try fm.createDirectory(at: sourceRootURL, withIntermediateDirectories: true)
        try fm.moveItem(at: mountedFolderURL, to: folderURL)
        return folderURL
    }

    private func reconcileClaudeMount(sourceURL: URL, mountRootURL: URL) throws {
        let mount = mountRootURL.appendingPathComponent(sourceURL.lastPathComponent)
        guard mount != sourceURL else { return }
        _ = try SkillMountSync.ensureMount(sourceURL: sourceURL, mountRoot: mountRootURL)
    }

    static func resolveRemotePath(name: String, source: String, coordinates: SkillSourceCoordinates?, paths: [String]) -> SkillRemotePath {
        let isTreeURL = URL(string: source)?.path.contains("/tree/") == true
        let scoped = paths.filter { path in
            guard isTreeURL, let scope = coordinates?.path else { return true }
            return path == scope || path.hasPrefix(scope + "/")
        }
        let matches = scoped.filter { ($0 as NSString).lastPathComponent == name }
        if matches.count == 1 { return .resolved(matches[0]) }
        if scoped.count == 1 { return .resolved(scoped[0]) }
        // Exact folder URLs remain usable when GitHub tree lookup is unavailable.
        if paths.isEmpty, isTreeURL, let path = coordinates?.path, (path as NSString).lastPathComponent == name {
            return .resolved(path)
        }
        return .unresolved
    }

    static func inferName(fromSource source: String) -> String {
        let trimmed = source.trimmingCharacters(in: .whitespaces)
        let last = trimmed.split(separator: "/").last.map(String.init) ?? trimmed
        return last.replacingOccurrences(of: ".git", with: "")
    }
}
