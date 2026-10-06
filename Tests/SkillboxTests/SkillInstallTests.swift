import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Skillbox

@MainActor
struct SkillInstallTests {
    @Test func terminalChunksBecomeReadableProgressAndBoundedErrors() {
        var output = SkillInstallOutput()
        output.append("\u{1B}[2K\r◇ Cloning repository…\n")
        #expect(output.stage == .downloading)
        output.append("│ Found 1 ski")
        output.append("ll\n\u{1B}[32mInstallation Summary\u{1B}[0m\n")
        #expect(output.stage == .installing)
        output.append("└ Installation complete!\n")
        #expect(output.stage == .finishing)
        #expect(SkillInstallOutput.plainText("\u{1B}[32mhello\u{1B}[0m\rworld") == "hello\nworld")
        let error = SkillInstallOutput.failureMessage(output: "ASCII banner\n\u{1B}[31m│ fatal: repository not found\u{1B}[0m\n", exitCode: 1)
        #expect(error == "Could not install the skill. fatal: repository not found")
        #expect(!error.contains("ASCII banner"))
    }

    @Test func actualInstalledNamesComeFromTerminalPaths() {
        let output = "│ \u{1B}[32m~/.agents/skills/teach\u{1B}[0m\n│ ~/.claude/skills/teach\n│ /Users/test/.agents/skills/tdd\n"
        #expect(SkillInstallOutput.installedNames(output: output) == ["teach", "tdd"])
    }

    @Test func downloadCreatesDiscoverableSkillsAndShowsFriendlyCompletion() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("skillbox-download-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let agents = root.appendingPathComponent("agents")
        let claude = root.appendingPathComponent("claude")
        let service = RemoteSkillService(cli: FixtureInstallCLI(mount: claude), registry: FixtureInstallRegistry())
        let model = SkillInstallModel()
        await model.installSkill(source: "owner/collection", rootPath: agents.path, mountPath: claude.path, service: service)
        #expect(model.phase == .done)
        #expect(model.installedNames == ["teach", "tdd"])
        #expect(model.errorMessage == nil)
        let installed = try SkillScanner.scan(rootURL: agents)
        #expect(Set(installed.map(\.name)) == ["teach", "tdd"])
        #expect(installed.allSatisfy { $0.provenance?.sha == "fixture-sha" })
        for skill in installed {
            #expect(SkillSourceCoordinates.parse(provenance: try #require(skill.provenance))?.path == (skill.name == "teach" ? "skills/productivity/teach" : "skills/engineering/tdd"))
        }
        for name in model.installedNames {
            #expect(SkillMountSync.isSymlink(claude.appendingPathComponent(name)))
        }
    }

    @Test func downloadFailureShowsReasonWithoutTerminalFormatting() async {
        let service = RemoteSkillService(cli: FixtureInstallCLI(mount: URL(fileURLWithPath: "/tmp/unused"), shouldFail: true), registry: FixtureInstallRegistry())
        let model = SkillInstallModel()
        await model.installSkill(source: "owner/missing", rootPath: "/tmp/unused", mountPath: "/tmp/unused", service: service)
        #expect(model.phase == .input)
        #expect(model.installedNames.isEmpty)
        #expect(model.errorMessage == "Could not install the skill. fatal: repository not found")
    }

    @Test func canonicalAndClaudeCopiesBecomeOneSourceWithoutLosingClaudeFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("skillbox-double-copy-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let agents = root.appendingPathComponent("agents")
        let claude = root.appendingPathComponent("claude")
        for name in ["teach", "tdd"] {
            let folder = agents.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try "---\nname: \(name)\ndescription: Canonical\n---".write(to: folder.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        }
        let service = RemoteSkillService(cli: FixtureInstallCLI(mount: claude), registry: FixtureInstallRegistry())
        let result = try await service.install(source: "owner/collection", rootPath: agents.path, claudeMountPath: claude.path) { _ in }
        #expect(result.names == ["teach", "tdd"])
        #expect(SkillMountSync.isSymlink(claude.appendingPathComponent("teach")))
        let backups = try FileManager.default.contentsOfDirectory(at: agents.appendingPathComponent(".skillbox-backups"), includingPropertiesForKeys: nil)
        #expect(backups.count == 2)
        for name in result.names {
            let content = try String(contentsOf: agents.appendingPathComponent(name + "/SKILL.md"), encoding: .utf8)
            #expect(content.contains("Fixture skill"))
        }
        for backup in backups {
            let folders = try FileManager.default.contentsOfDirectory(at: backup, includingPropertiesForKeys: nil)
            let content = try String(contentsOf: try #require(folders.first).appendingPathComponent("SKILL.md"), encoding: .utf8)
            #expect(content.contains("Canonical"))
        }
        #expect(try SkillScanner.scan(rootURL: agents).count == 2)
    }

    @Test func remotePathsRespectCollectionsRootSkillsAndUncertainty() {
        let source = "https://github.com/owner/repo/tree/main/skills/productivity"
        let coordinates = SkillSourceCoordinates.parse(provenance: SkillProvenance(source: source))
        #expect(RemoteSkillService.resolveRemotePath(name: "teach", source: source, coordinates: coordinates, paths: ["skills/productivity/teach", "skills/engineering/teach"]) == .resolved("skills/productivity/teach"))
        #expect(RemoteSkillService.resolveRemotePath(name: "custom-name", source: "owner/repo", coordinates: coordinates, paths: [""]) == .resolved(""))
        #expect(RemoteSkillService.resolveRemotePath(name: "unknown", source: "owner/repo", coordinates: coordinates, paths: []) == .unresolved)
        #expect(SkillSourceCoordinates.parse(provenance: SkillProvenance(source: "owner/repo", remotePath: .unresolved)) == nil)
        #expect(SkillSourceCoordinates.parse(provenance: SkillProvenance(source: "owner/repo")) != nil)
    }

    @Test func renderInstallProgressHarness() throws {
        for (name, stage, installed) in [
            ("downloading", SkillInstallStage.downloading, [String]()),
            ("installing", SkillInstallStage.installing, [String]()),
            ("installed", SkillInstallStage.finishing, ["teach", "tdd"]),
        ] {
            let renderer = ImageRenderer(content:
                SkillInstallProgressView(source: "github.com/owner/collection", stage: stage, installedNames: installed)
                    .padding(20).frame(width: 360, height: 380, alignment: .top)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .environment(\.colorScheme, .dark)
            )
            renderer.scale = 2
            let image = try #require(renderer.cgImage)
            #expect(image.width == 720)
            if let directory = ProcessInfo.processInfo.environment["SKILLBOX_RENDER_DIR"] {
                let url = URL(fileURLWithPath: directory)
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                let bitmap = NSBitmapImageRep(cgImage: image)
                let png = try #require(bitmap.representation(using: .png, properties: [:]))
                try png.write(to: url.appendingPathComponent("install-\(name).png"))
            }
        }
    }
}

private struct FixtureInstallCLI: SkillsCLIRunning {
    let mount: URL
    var shouldFail = false

    func install(_ options: SkillsCLI.InstallOptions, stream: @escaping @Sendable (String) -> Void) async throws -> SkillsCLI.RunResult {
        if shouldFail {
            return .init(exitCode: 1, combinedOutput: "\u{1B}[31m│ fatal: repository not found\u{1B}[0m")
        }
        stream("\u{1B}[2K\r◇ Cloning repository…\n")
        stream("│ Found 2 skills\n")
        for name in ["teach", "tdd"] {
            let folder = mount.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try "---\nname: \(name)\ndescription: Fixture skill\n---\n# Instructions\n".write(to: folder.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        }
        let summary = "│ ~/.claude/skills/teach\n│ ~/.claude/skills/tdd\n└ Installation complete!\n"
        stream(summary)
        return .init(exitCode: 0, combinedOutput: summary)
    }

    func update(skillName: String, stream: @escaping @Sendable (String) -> Void) async throws -> SkillsCLI.RunResult {
        .init(exitCode: 0, combinedOutput: "")
    }
}

private struct FixtureInstallRegistry: SkillRegistryFetching {
    func skillPaths(repo: String, branch: String) async throws -> [String] {
        ["skills/productivity/teach", "skills/engineering/tdd"]
    }
    func latestSHA(repo: String, branch: String, path: String) async throws -> String? {
        ["skills/productivity/teach", "skills/engineering/tdd"].contains(path) ? "fixture-sha" : nil
    }
}
