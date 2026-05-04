import Testing
import Foundation
@testable import Skillbox

struct SkillProvenanceTests {
    private func makeFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("skillbox-provenance-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    @Test func roundTrip_preservesAllFields() throws {
        let folder = try makeFolder()
        defer { cleanup(folder) }

        let installedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let lastChecked = Date(timeIntervalSince1970: 1_700_001_234)
        let original = SkillProvenance(
            source: "vercel-labs/agent-skills",
            skill: "find-skills",
            ref: "main",
            sha: "abc123",
            installedAt: installedAt,
            lastCheckedAt: lastChecked,
            latestKnownSHA: "def456"
        )

        try SkillProvenanceStore.write(original, to: folder)
        let decoded = SkillProvenanceStore.read(from: folder)

        #expect(decoded == original)
    }

    @Test func read_returnsNilWhenSidecarMissing() throws {
        let folder = try makeFolder()
        defer { cleanup(folder) }

        #expect(SkillProvenanceStore.read(from: folder) == nil)
    }

    @Test func hasUpdate_trueOnlyWhenLatestSHADiffersFromSHA() {
        var p = SkillProvenance(source: "owner/repo", sha: "aaa", latestKnownSHA: "aaa")
        #expect(p.hasUpdate == false)

        p.latestKnownSHA = "bbb"
        #expect(p.hasUpdate == true)

        p.latestKnownSHA = nil
        #expect(p.hasUpdate == false)

        p.latestKnownSHA = ""
        #expect(p.hasUpdate == false)
    }

    @Test func scanner_attachesProvenanceWhenSidecarPresent() throws {
        let root = try makeFolder()
        defer { cleanup(root) }

        let skillFolder = root.appendingPathComponent("frontend-design")
        try FileManager.default.createDirectory(at: skillFolder, withIntermediateDirectories: true)
        let skillMd = skillFolder.appendingPathComponent("SKILL.md")
        try """
        ---
        name: frontend-design
        description: Builds production-grade frontend interfaces.
        ---

        Body
        """.write(to: skillMd, atomically: true, encoding: .utf8)

        let provenance = SkillProvenance(
            source: "vercel-labs/agent-skills",
            skill: "frontend-design"
        )
        try SkillProvenanceStore.write(provenance, to: skillFolder)

        let result = try SkillScanner.scan(rootURL: root)
        #expect(result.count == 1)
        #expect(result.first?.provenance?.source == "vercel-labs/agent-skills")
        #expect(result.first?.provenance?.skill == "frontend-design")
    }

    @Test func scanner_leavesProvenanceNilWhenSidecarMissing() throws {
        let root = try makeFolder()
        defer { cleanup(root) }

        let skillFolder = root.appendingPathComponent("local-skill")
        try FileManager.default.createDirectory(at: skillFolder, withIntermediateDirectories: true)
        let skillMd = skillFolder.appendingPathComponent("SKILL.md")
        try """
        ---
        name: local-skill
        description: Local
        ---
        """.write(to: skillMd, atomically: true, encoding: .utf8)

        let result = try SkillScanner.scan(rootURL: root)
        #expect(result.count == 1)
        #expect(result.first?.provenance == nil)
    }
}
