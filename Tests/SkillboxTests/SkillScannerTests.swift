import Testing
import Foundation
@testable import Skillbox

struct SkillScannerTests {
    private func makeFixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("skillbox-skill-scanner-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func writeFile(at url: URL, contents: String) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    @Test func scan_emptyRoot_returnsEmpty() throws {
        let root = try makeFixture()
        defer { cleanup(root) }

        let result = try SkillScanner.scan(rootURL: root)
        #expect(result.isEmpty)
    }

    @Test func scan_folderWithoutSkillMd_isIgnored() throws {
        let root = try makeFixture()
        defer { cleanup(root) }

        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("not-a-skill"),
            withIntermediateDirectories: true
        )

        let result = try SkillScanner.scan(rootURL: root)
        #expect(result.isEmpty)
    }

    @Test func scan_parsesFrontmatterFields() throws {
        let root = try makeFixture()
        defer { cleanup(root) }

        try writeFile(
            at: root.appendingPathComponent("widget").appendingPathComponent("SKILL.md"),
            contents: """
            ---
            name: widget skill
            description: builds widgets when asked
            ---

            Body.
            """
        )

        let result = try SkillScanner.scan(rootURL: root)
        let skill = try #require(result.first)
        #expect(skill.name == "widget skill")
        #expect(skill.description == "builds widgets when asked")
    }

    @Test func scan_missingFrontmatter_isSkipped() throws {
        let root = try makeFixture()
        defer { cleanup(root) }

        try writeFile(
            at: root.appendingPathComponent("plain").appendingPathComponent("SKILL.md"),
            contents: "no frontmatter here"
        )

        let result = try SkillScanner.scan(rootURL: root)
        #expect(result.isEmpty)
    }

    @Test func scan_aggregatesMultipleSkills() throws {
        let root = try makeFixture()
        defer { cleanup(root) }

        try writeFile(
            at: root.appendingPathComponent("alpha").appendingPathComponent("SKILL.md"),
            contents: "---\nname: alpha\ndescription: a\n---\n"
        )
        try writeFile(
            at: root.appendingPathComponent("beta").appendingPathComponent("SKILL.md"),
            contents: "---\nname: beta\ndescription: b\n---\n"
        )

        let result = try SkillScanner.scan(rootURL: root)
        #expect(Set(result.map(\.name)) == ["alpha", "beta"])
    }

    @Test func scan_fallsBackToFolderNameWhenFrontmatterMissingName() throws {
        let root = try makeFixture()
        defer { cleanup(root) }

        try writeFile(
            at: root.appendingPathComponent("foldername").appendingPathComponent("SKILL.md"),
            contents: "---\ndescription: no name field\n---\n"
        )

        let result = try SkillScanner.scan(rootURL: root)
        let skill = try #require(result.first)
        #expect(skill.name == "foldername")
    }
}
