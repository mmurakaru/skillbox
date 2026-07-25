import Testing
import Foundation
@testable import Skillbox

@MainActor
struct InstallReconciliationTests {
    @Test func install_movesClaudeCliFolderIntoAgentsAndCreatesMountSymlink() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("skillbox-install-reconcile-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let agents = root.appendingPathComponent("agents")
        let claude = root.appendingPathComponent("claude")
        try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: true)

        let cli = ReconcileCLI { options in
            let skillName = options.skill ?? options.source.split(separator: "/").last.map(String.init) ?? options.source
            let folder = claude.appendingPathComponent(skillName)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try "---\nname: \(skillName)\ndescription: Installed by fake CLI\n---\n".write(
                to: folder.appendingPathComponent("SKILL.md"),
                atomically: true,
                encoding: .utf8
            )
        }
        let service = RemoteSkillService(
            cli: cli,
            registry: ReconcileRegistry(),
            fileSystem: DefaultSkillsFileSystem()
        )

        let installed = try await service.install(
            source: "owner/cool-skill",
            skill: nil,
            rootPath: agents.path,
            claudeMountPath: claude.path
        ) { _ in }

        let agentsFolder = agents.appendingPathComponent("cool-skill")
        let claudeMount = claude.appendingPathComponent("cool-skill")
        #expect(installed.folderURL.path == agentsFolder.path)
        #expect(FileManager.default.fileExists(atPath: agentsFolder.appendingPathComponent("SKILL.md").path))
        #expect(SkillMountSync.isSymlink(claudeMount))
        #expect(claudeMount.resolvingSymlinksInPath().path == agentsFolder.path)
        #expect(SkillProvenanceStore.read(from: agentsFolder)?.source == "owner/cool-skill")
    }
}

private struct ReconcileCLI: SkillsCLIRunning {
    let onInstall: @Sendable (SkillsCLI.InstallOptions) throws -> Void

    func install(
        _ options: SkillsCLI.InstallOptions,
        stream: @escaping @Sendable (String) -> Void
    ) async throws -> SkillsCLI.RunResult {
        try onInstall(options)
        return SkillsCLI.RunResult(exitCode: 0, combinedOutput: "ok")
    }

    func update(
        skillName: String,
        stream: @escaping @Sendable (String) -> Void
    ) async throws -> SkillsCLI.RunResult {
        SkillsCLI.RunResult(exitCode: 0, combinedOutput: "ok")
    }
}

private struct ReconcileRegistry: SkillRegistryFetching {
    func latestSHA(repo: String, branch: String, path: String) async throws -> String? { nil }
}
