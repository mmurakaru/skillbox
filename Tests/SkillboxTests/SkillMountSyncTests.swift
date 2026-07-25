import Testing
import Foundation
@testable import Skillbox

struct SkillMountSyncTests {
    private func makeFixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("skillbox-mount-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test func ensureAll_createsClaudeSymlinksForAgentsSkills() throws {
        let root = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let agents = root.appendingPathComponent("agents")
        let claude = root.appendingPathComponent("claude")
        let skill = agents.appendingPathComponent("diagnose")
        try FileManager.default.createDirectory(at: skill, withIntermediateDirectories: true)
        try "---\nname: diagnose\ndescription: Diagnose things\n---\n".write(
            to: skill.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        let report = try SkillMountSync.ensureAll(sourceRoot: agents, mountRoot: claude)

        #expect(report.created == ["diagnose"])
        let link = claude.appendingPathComponent("diagnose")
        #expect(SkillMountSync.isSymlink(link))
        #expect(link.resolvingSymlinksInPath().path == skill.path)
        #expect(FileManager.default.fileExists(atPath: link.appendingPathComponent("SKILL.md").path))
    }

    @Test func ensureAll_repairsWrongSymlinkButLeavesRealConflicts() throws {
        let root = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let agents = root.appendingPathComponent("agents")
        let claude = root.appendingPathComponent("claude")
        let skill = agents.appendingPathComponent("alpha")
        let other = root.appendingPathComponent("other")
        try FileManager.default.createDirectory(at: skill, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: true)
        try "---\nname: alpha\ndescription: Alpha\n---\n".write(
            to: skill.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.createSymbolicLink(
            atPath: claude.appendingPathComponent("alpha").path,
            withDestinationPath: other.path
        )

        let report = try SkillMountSync.ensureAll(sourceRoot: agents, mountRoot: claude)

        #expect(report.repaired == ["alpha"])
        #expect(claude.appendingPathComponent("alpha").resolvingSymlinksInPath().path == skill.path)
    }

    @Test func removeMount_removesOnlySymlinkMount() throws {
        let root = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let agents = root.appendingPathComponent("agents")
        let claude = root.appendingPathComponent("claude")
        let skill = agents.appendingPathComponent("delete-me")
        try FileManager.default.createDirectory(at: skill, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: true)
        try "---\nname: delete-me\ndescription: Delete me\n---\n".write(
            to: skill.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )
        _ = try SkillMountSync.ensureMount(sourceURL: skill, mountRoot: claude)

        try SkillMountSync.removeMount(named: "delete-me", mountRoot: claude)

        #expect(!FileManager.default.fileExists(atPath: claude.appendingPathComponent("delete-me").path))
        #expect(FileManager.default.fileExists(atPath: skill.appendingPathComponent("SKILL.md").path))
    }
}
