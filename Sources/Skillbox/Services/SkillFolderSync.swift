import Foundation
import Observation

/// Mirrors a remote skill folder over HTTPS (GitHub Contents + raw content).
/// SHA-gated: no-op when `provenance.sha == latestSHA(remote)`.
@MainActor
@Observable
final class SkillFolderSync {
    private(set) var inFlight: Set<String> = []
    private(set) var lastError: String?

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    enum SyncOutcome: Equatable {
        /// Local SHA already matches upstream - no files written.
        case upToDate(sha: String)
        /// Files were mirrored from upstream.
        case mirrored(sha: String, fileCount: Int)
        /// Source string could not be parsed into `owner/repo/path` coordinates.
        case unresolvableSource
    }

    enum SyncError: LocalizedError {
        case missingProvenance
        case unresolvableSource(String)
        case underlying(Error)

        var errorDescription: String? {
            switch self {
            case .missingProvenance:
                return "Skill has no provenance sidecar - nothing to sync."
            case .unresolvableSource(let raw):
                return "Could not parse remote source \"\(raw)\" into owner/repo coordinates."
            case .underlying(let err):
                return err.localizedDescription
            }
        }
    }

    // MARK: - Public

    /// Sync one skill. Returns the outcome; provenance file is updated on success.
    @discardableResult
    func sync(_ skill: Skill) async throws -> SyncOutcome {
        guard let provenance = skill.provenance else { throw SyncError.missingProvenance }
        guard let coords = SkillSourceCoordinates.parse(provenance: provenance) else {
            throw SyncError.unresolvableSource(provenance.source)
        }

        inFlight.insert(skill.id)
        defer { inFlight.remove(skill.id) }

        do {
            let latest = try await SkillRegistry.latestSHA(
                repo: coords.repo,
                branch: coords.branch,
                path: coords.path,
                session: session
            )

            // SHA gating: if upstream SHA is known and matches local, no-op (but still stamp lastCheckedAt).
            if let latest, latest == provenance.sha {
                var updated = provenance
                updated.lastCheckedAt = Date()
                updated.latestKnownSHA = latest
                try? SkillProvenanceStore.write(updated, to: skill.folderURL)
                lastError = nil
                return .upToDate(sha: latest)
            }

            let files = try await SkillRegistry.listAll(
                repo: coords.repo,
                branch: coords.branch,
                path: coords.path,
                session: session
            )

            for file in files {
                // Skip the provenance sidecar even if upstream happens to contain a stray copy.
                if file.relativePath == SkillProvenance.sidecarFilename { continue }
                let data = try await SkillRegistry.fetchRawData(
                    repo: coords.repo,
                    branch: coords.branch,
                    path: file.absolutePath,
                    session: session
                )
                try write(data: data, to: skill.folderURL.appendingPathComponent(file.relativePath))
            }

            var updated = provenance
            let now = Date()
            updated.lastCheckedAt = now
            if let latest {
                updated.sha = latest
                updated.latestKnownSHA = latest
            }
            try SkillProvenanceStore.write(updated, to: skill.folderURL)

            lastError = nil
            return .mirrored(sha: latest ?? "", fileCount: files.count)
        } catch let error as SyncError {
            lastError = error.errorDescription
            throw error
        } catch {
            lastError = error.localizedDescription
            throw SyncError.underlying(error)
        }
    }

    /// Sync every skill in the input that has a provenance sidecar. Errors per-skill are swallowed.
    func syncAll(_ skills: [Skill]) async {
        for skill in skills where skill.provenance != nil {
            _ = try? await sync(skill)
        }
    }

    /// Whether a given skill is currently mid-sync (UI uses this to swap in a spinner).
    func isSyncing(_ skill: Skill) -> Bool {
        inFlight.contains(skill.id)
    }

    // MARK: - Private

    private func write(data: Data, to fileURL: URL) throws {
        let parent = fileURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parent.path) {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        }
        try data.write(to: fileURL, options: .atomic)
    }
}
