import Testing
import Foundation
@testable import Skillbox

@MainActor
struct RemoteSkillServiceTests {

    // MARK: - Install

    @Test func installing_a_skill_writes_a_sidecar_with_the_source_and_latest_sha() async throws {
        let cli = FakeCLI(installResult: .success(exitCode: 0))
        let registry = FakeRegistry(latest: ["vercel-labs/agent-skills/skills/find-skills": "sha-abc"])
        let fs = InMemoryFileSystem()
        let service = RemoteSkillService(cli: cli, registry: registry, fileSystem: fs)

        _ = try await service.install(
            source: "vercel-labs/agent-skills",
            skill: "find-skills",
            rootPath: "/Users/test/skills"
        ) { _ in }

        let folder = URL(fileURLWithPath: "/Users/test/skills/find-skills")
        let stored = try #require(fs.readProvenance(at: folder))
        #expect(stored.source == "vercel-labs/agent-skills")
        #expect(stored.skill == "find-skills")
        #expect(stored.sha == "sha-abc")
        #expect(stored.latestKnownSHA == "sha-abc")
    }

    @Test func installing_a_skill_streams_the_cli_output_to_the_caller() async throws {
        let cli = FakeCLI(installResult: .success(exitCode: 0, streamChunks: ["fetching…\n", "done\n"]))
        let service = RemoteSkillService(cli: cli, registry: FakeRegistry(), fileSystem: InMemoryFileSystem())

        var captured = ""
        _ = try await service.install(
            source: "owner/repo",
            skill: "frontend-design",
            rootPath: "/tmp/skills"
        ) { chunk in
            captured += chunk
        }

        #expect(captured == "fetching…\ndone\n")
    }

    @Test func installing_a_skill_with_no_skill_name_uses_the_repo_basename() async throws {
        let cli = FakeCLI(installResult: .success(exitCode: 0))
        let fs = InMemoryFileSystem()
        let service = RemoteSkillService(cli: cli, registry: FakeRegistry(), fileSystem: fs)

        let installed = try await service.install(
            source: "https://github.com/owner/cool-skill.git",
            skill: nil,
            rootPath: "/tmp/skills"
        ) { _ in }

        #expect(installed.name == "cool-skill")
        #expect(installed.folderURL == URL(fileURLWithPath: "/tmp/skills/cool-skill"))
    }

    @Test func installing_a_skill_when_the_cli_fails_throws_and_writes_no_sidecar() async throws {
        let cli = FakeCLI(installResult: .success(exitCode: 1, output: "rate limited"))
        let fs = InMemoryFileSystem()
        let service = RemoteSkillService(cli: cli, registry: FakeRegistry(), fileSystem: fs)

        await #expect(throws: RemoteSkillService.ServiceError.self) {
            _ = try await service.install(
                source: "owner/repo",
                skill: "x",
                rootPath: "/tmp/skills"
            ) { _ in }
        }

        #expect(fs.writes.isEmpty)
    }

    @Test func installing_a_skill_when_the_folder_is_missing_throws() async throws {
        let cli = FakeCLI(installResult: .success(exitCode: 0))
        let fs = InMemoryFileSystem(folderExists: false)
        let service = RemoteSkillService(cli: cli, registry: FakeRegistry(), fileSystem: fs)

        await #expect(throws: RemoteSkillService.ServiceError.self) {
            _ = try await service.install(
                source: "owner/repo",
                skill: "x",
                rootPath: "/tmp/skills"
            ) { _ in }
        }
    }

    @Test func installing_a_skill_records_provenance_even_when_the_registry_is_unreachable() async throws {
        let cli = FakeCLI(installResult: .success(exitCode: 0))
        let registry = FakeRegistry(failureMode: .always)
        let fs = InMemoryFileSystem()
        let service = RemoteSkillService(cli: cli, registry: registry, fileSystem: fs)

        _ = try await service.install(
            source: "owner/repo",
            skill: "x",
            rootPath: "/tmp/skills"
        ) { _ in }

        let folder = URL(fileURLWithPath: "/tmp/skills/x")
        let stored = try #require(fs.readProvenance(at: folder))
        #expect(stored.sha == nil)
        #expect(stored.latestKnownSHA == nil)
    }

    // MARK: - Update

    @Test func updating_a_skill_runs_the_cli_then_refreshes_the_sha() async throws {
        let cli = FakeCLI(updateResult: .success(exitCode: 0))
        let registry = FakeRegistry(latest: ["owner/repo/skills/x": "sha-new"])
        let fs = InMemoryFileSystem()
        let service = RemoteSkillService(cli: cli, registry: registry, fileSystem: fs)

        let folder = URL(fileURLWithPath: "/tmp/skills/x")
        let initial = SkillProvenance(source: "owner/repo", skill: "x", ref: "main", sha: "sha-old", latestKnownSHA: "sha-old")
        try fs.writeProvenance(initial, to: folder)
        let skill = Skill(name: "x", description: "", folderURL: folder, modifiedAt: Date(), provenance: initial)

        try await service.update(skill) { _ in }

        let stored = try #require(fs.readProvenance(at: folder))
        #expect(stored.sha == "sha-new")
        #expect(stored.latestKnownSHA == "sha-new")
    }

    @Test func updating_when_the_cli_fails_does_not_overwrite_the_existing_sidecar() async throws {
        let cli = FakeCLI(updateResult: .success(exitCode: 2, output: "boom"))
        let fs = InMemoryFileSystem()
        let service = RemoteSkillService(cli: cli, registry: FakeRegistry(), fileSystem: fs)

        let folder = URL(fileURLWithPath: "/tmp/skills/x")
        let initial = SkillProvenance(source: "owner/repo", skill: "x", sha: "sha-old", latestKnownSHA: "sha-old")
        try fs.writeProvenance(initial, to: folder)
        let skill = Skill(name: "x", description: "", folderURL: folder, modifiedAt: Date(), provenance: initial)

        await #expect(throws: RemoteSkillService.ServiceError.self) {
            try await service.update(skill) { _ in }
        }

        let stored = try #require(fs.readProvenance(at: folder))
        #expect(stored.sha == "sha-old")
    }

    @Test func updating_a_skill_without_provenance_is_a_no_op() async throws {
        let cli = FakeCLI()
        let service = RemoteSkillService(cli: cli, registry: FakeRegistry(), fileSystem: InMemoryFileSystem())

        let skill = Skill(
            name: "local-only",
            description: "",
            folderURL: URL(fileURLWithPath: "/tmp/skills/local-only"),
            modifiedAt: Date(),
            provenance: nil
        )

        try await service.update(skill) { _ in }
        #expect(cli.updateCalls.isEmpty)
    }

    // MARK: - Check for updates

    @Test func check_for_updates_marks_a_row_when_the_origin_sha_advances() async throws {
        let registry = FakeRegistry(latest: ["owner/repo/skills/x": "sha-new"])
        let fs = InMemoryFileSystem()
        let service = RemoteSkillService(cli: FakeCLI(), registry: registry, fileSystem: fs)

        let folder = URL(fileURLWithPath: "/tmp/skills/x")
        let provenance = SkillProvenance(source: "owner/repo", skill: "x", sha: "sha-old", latestKnownSHA: "sha-old")
        try fs.writeProvenance(provenance, to: folder)
        let skill = Skill(name: "x", description: "", folderURL: folder, modifiedAt: Date(), provenance: provenance)

        await service.checkForUpdates([skill])

        let stored = try #require(fs.readProvenance(at: folder))
        #expect(stored.sha == "sha-old")        // installed SHA is preserved
        #expect(stored.latestKnownSHA == "sha-new")  // upstream advance is recorded
        #expect(stored.hasUpdate == true)
    }

    @Test func check_for_updates_skips_skills_whose_source_cannot_be_parsed() async throws {
        let registry = FakeRegistry()
        let fs = InMemoryFileSystem()
        let service = RemoteSkillService(cli: FakeCLI(), registry: registry, fileSystem: fs)

        let folder = URL(fileURLWithPath: "/tmp/skills/x")
        let provenance = SkillProvenance(source: "/local/unparseable", skill: "x")
        try fs.writeProvenance(provenance, to: folder)
        let skill = Skill(name: "x", description: "", folderURL: folder, modifiedAt: Date(), provenance: provenance)

        await service.checkForUpdates([skill])

        #expect(registry.shaCalls.isEmpty)
    }

    @Test func check_for_updates_keeps_going_when_one_registry_call_fails() async throws {
        let registry = FakeRegistry(
            latest: ["owner/repo/skills/good": "sha-good"],
            failingPaths: ["owner/repo/skills/bad"]
        )
        let fs = InMemoryFileSystem()
        let service = RemoteSkillService(cli: FakeCLI(), registry: registry, fileSystem: fs)

        let goodFolder = URL(fileURLWithPath: "/tmp/skills/good")
        let goodProvenance = SkillProvenance(source: "owner/repo", skill: "good", sha: "sha-old")
        try fs.writeProvenance(goodProvenance, to: goodFolder)

        let badFolder = URL(fileURLWithPath: "/tmp/skills/bad")
        let badProvenance = SkillProvenance(source: "owner/repo", skill: "bad", sha: "sha-bad-old")
        try fs.writeProvenance(badProvenance, to: badFolder)

        let goodSkill = Skill(name: "good", description: "", folderURL: goodFolder, modifiedAt: Date(), provenance: goodProvenance)
        let badSkill = Skill(name: "bad", description: "", folderURL: badFolder, modifiedAt: Date(), provenance: badProvenance)

        await service.checkForUpdates([goodSkill, badSkill])

        let goodStored = try #require(fs.readProvenance(at: goodFolder))
        let badStored = try #require(fs.readProvenance(at: badFolder))
        #expect(goodStored.latestKnownSHA == "sha-good")
        #expect(badStored.latestKnownSHA == nil)  // never written, sidecar untouched
    }

    // MARK: - Helpers

    @Test func inferred_name_strips_dot_git_and_takes_basename() {
        #expect(RemoteSkillService.inferName(fromSource: "owner/repo") == "repo")
        #expect(RemoteSkillService.inferName(fromSource: "https://github.com/owner/repo.git") == "repo")
        #expect(RemoteSkillService.inferName(fromSource: "git@github.com:owner/repo.git") == "repo")
    }
}

// MARK: - Test doubles

private final class FakeCLI: SkillsCLIRunning, @unchecked Sendable {
    struct Outcome {
        var exitCode: Int32
        var output: String
        var streamChunks: [String]

        static func success(exitCode: Int32 = 0, output: String = "", streamChunks: [String] = []) -> Outcome {
            Outcome(exitCode: exitCode, output: output, streamChunks: streamChunks)
        }
    }

    var installResult: Outcome
    var updateResult: Outcome

    private(set) var installCalls: [SkillsCLI.InstallOptions] = []
    private(set) var updateCalls: [String] = []

    init(installResult: Outcome = .success(), updateResult: Outcome = .success()) {
        self.installResult = installResult
        self.updateResult = updateResult
    }

    func install(
        _ options: SkillsCLI.InstallOptions,
        stream: @escaping @Sendable (String) -> Void
    ) async throws -> SkillsCLI.RunResult {
        installCalls.append(options)
        for chunk in installResult.streamChunks { stream(chunk) }
        return SkillsCLI.RunResult(exitCode: installResult.exitCode, combinedOutput: installResult.output)
    }

    func update(
        skillName: String,
        stream: @escaping @Sendable (String) -> Void
    ) async throws -> SkillsCLI.RunResult {
        updateCalls.append(skillName)
        for chunk in updateResult.streamChunks { stream(chunk) }
        return SkillsCLI.RunResult(exitCode: updateResult.exitCode, combinedOutput: updateResult.output)
    }
}

private final class FakeRegistry: SkillRegistryFetching, @unchecked Sendable {
    enum FailureMode { case never, always }

    /// Map of `"<repo>/<path>"` → SHA returned for that path.
    var latest: [String: String]
    /// Set of `"<repo>/<path>"` keys that should throw instead of returning.
    var failingPaths: Set<String>
    var failureMode: FailureMode

    private(set) var shaCalls: [String] = []

    init(latest: [String: String] = [:], failingPaths: Set<String> = [], failureMode: FailureMode = .never) {
        self.latest = latest
        self.failingPaths = failingPaths
        self.failureMode = failureMode
    }

    struct ForcedFailure: Error {}

    func latestSHA(repo: String, branch: String, path: String) async throws -> String? {
        let key = "\(repo)/\(path)"
        shaCalls.append(key)
        if failureMode == .always || failingPaths.contains(key) { throw ForcedFailure() }
        return latest[key]
    }
}

private final class InMemoryFileSystem: SkillsFileSystem, @unchecked Sendable {
    private var store: [String: SkillProvenance] = [:]
    private(set) var writes: [(URL, SkillProvenance)] = []
    var folderExistsResult: Bool

    init(folderExists: Bool = true) { self.folderExistsResult = folderExists }

    func readProvenance(at folderURL: URL) -> SkillProvenance? { store[folderURL.path] }

    func writeProvenance(_ provenance: SkillProvenance, to folderURL: URL) throws {
        store[folderURL.path] = provenance
        writes.append((folderURL, provenance))
    }

    func folderExists(at url: URL) -> Bool { folderExistsResult }
}
