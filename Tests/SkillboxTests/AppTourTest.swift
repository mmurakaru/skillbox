import Testing
import Foundation
@testable import Skillbox

/// One end-to-end walkthrough of the remote-skill lifecycle:
/// install → check for updates → run update.
///
/// Reads top-to-bottom like the README — each step asserts the user-visible
/// outcome before moving on. If you want to understand what the app does,
/// start here.
@MainActor
struct AppTourTest {
    @Test func a_user_installs_a_skill_then_keeps_it_up_to_date() async throws {
        // Setup: a CLI that always succeeds, a registry that returns SHAs we control,
        // and an in-memory filesystem.
        let cli = TourCLI()
        let registry = TourRegistry()
        let fs = TourFileSystem()
        let service = RemoteSkillService(cli: cli, registry: registry, fileSystem: fs)

        // 1) The user pastes a registry URL and clicks Install.
        registry.setSHA(repo: "vercel-labs/agent-skills", path: "skills/find-skills", sha: "v1")

        let installed = try await service.install(
            source: "vercel-labs/agent-skills",
            skill: "find-skills",
            rootPath: "/Users/test/skills"
        ) { _ in }

        #expect(installed.name == "find-skills")
        #expect(cli.installCalls.count == 1)

        // 2) After install, a sidecar exists recording where the skill came from
        //    and the SHA at install time.
        let sidecar = try #require(fs.readProvenance(at: installed.folderURL))
        #expect(sidecar.source == "vercel-labs/agent-skills")
        #expect(sidecar.sha == "v1")
        #expect(sidecar.latestKnownSHA == "v1")
        #expect(sidecar.hasUpdate == false) // freshly installed, nothing to update

        // 3) Time passes. The upstream repo gets a new commit on this skill.
        registry.setSHA(repo: "vercel-labs/agent-skills", path: "skills/find-skills", sha: "v2")

        // 4) The user clicks "Check for updates".
        let skill = Skill(
            name: installed.name,
            description: "",
            folderURL: installed.folderURL,
            modifiedAt: Date(),
            provenance: sidecar
        )
        await service.checkForUpdates([skill])

        // The sidecar now records the upstream SHA, but the installed SHA hasn't moved
        // — the user hasn't accepted the upgrade yet.
        let afterCheck = try #require(fs.readProvenance(at: installed.folderURL))
        #expect(afterCheck.sha == "v1")
        #expect(afterCheck.latestKnownSHA == "v2")
        #expect(afterCheck.hasUpdate == true) // UI shows the "Update" pill

        // 5) The user clicks the "Update" pill.
        let staleSkill = Skill(
            name: skill.name,
            description: "",
            folderURL: skill.folderURL,
            modifiedAt: Date(),
            provenance: afterCheck
        )
        try await service.update(staleSkill) { _ in }

        // After update the installed SHA matches upstream and the row goes back to "current".
        let afterUpdate = try #require(fs.readProvenance(at: installed.folderURL))
        #expect(afterUpdate.sha == "v2")
        #expect(afterUpdate.latestKnownSHA == "v2")
        #expect(afterUpdate.hasUpdate == false)
        #expect(cli.updateCalls == ["find-skills"])
    }
}

// MARK: - Tour test doubles

private final class TourCLI: SkillsCLIRunning, @unchecked Sendable {
    private(set) var installCalls: [SkillsCLI.InstallOptions] = []
    private(set) var updateCalls: [String] = []

    func install(
        _ options: SkillsCLI.InstallOptions,
        stream: @escaping @Sendable (String) -> Void
    ) async throws -> SkillsCLI.RunResult {
        installCalls.append(options)
        return SkillsCLI.RunResult(exitCode: 0, combinedOutput: "")
    }

    func update(
        skillName: String,
        stream: @escaping @Sendable (String) -> Void
    ) async throws -> SkillsCLI.RunResult {
        updateCalls.append(skillName)
        return SkillsCLI.RunResult(exitCode: 0, combinedOutput: "")
    }
}

private final class TourRegistry: SkillRegistryFetching, @unchecked Sendable {
    private var shas: [String: String] = [:]

    func setSHA(repo: String, path: String, sha: String) {
        shas["\(repo)/\(path)"] = sha
    }

    func latestSHA(repo: String, branch: String, path: String) async throws -> String? {
        shas["\(repo)/\(path)"]
    }
}

private final class TourFileSystem: SkillsFileSystem, @unchecked Sendable {
    private var store: [String: SkillProvenance] = [:]

    func readProvenance(at folderURL: URL) -> SkillProvenance? { store[folderURL.path] }

    func writeProvenance(_ provenance: SkillProvenance, to folderURL: URL) throws {
        store[folderURL.path] = provenance
    }

    func folderExists(at url: URL) -> Bool { true }
}
