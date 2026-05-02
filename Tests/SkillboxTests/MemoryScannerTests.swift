import Testing
import Foundation
@testable import Skillbox

struct MemoryScannerTests {
    private func makeFixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("skillbox-scanner-tests-\(UUID().uuidString)")
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

        let result = try MemoryScanner.scan(rootURL: root)
        #expect(result.isEmpty)
    }

    @Test func scan_projectWithoutMemoryDir_isIgnored() throws {
        let root = try makeFixture()
        defer { cleanup(root) }

        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("-Users-alice-project"),
            withIntermediateDirectories: true
        )

        let result = try MemoryScanner.scan(rootURL: root)
        #expect(result.isEmpty)
    }

    @Test func scan_parsesFrontmatterFields() throws {
        let root = try makeFixture()
        defer { cleanup(root) }

        let memoryFile = root
            .appendingPathComponent("-Users-alice-project")
            .appendingPathComponent("memory")
            .appendingPathComponent("feedback_use_pnpm.md")

        try writeFile(at: memoryFile, contents: """
        ---
        name: Use pnpm not npm
        description: User prefers pnpm for all package install commands
        type: feedback
        ---

        Body of the memory entry.
        """)

        let result = try MemoryScanner.scan(rootURL: root)
        #expect(result.count == 1)
        let entry = try #require(result.first)
        #expect(entry.name == "Use pnpm not npm")
        #expect(entry.description == "User prefers pnpm for all package install commands")
        #expect(entry.type == .feedback)
    }

    @Test func scan_skipsMEMORYIndexFile() throws {
        let root = try makeFixture()
        defer { cleanup(root) }

        let memoryDir = root
            .appendingPathComponent("-Users-alice-project")
            .appendingPathComponent("memory")

        try writeFile(
            at: memoryDir.appendingPathComponent("MEMORY.md"),
            contents: "# Memory Index\n\n- [feedback_use_pnpm.md](feedback_use_pnpm.md) - line\n"
        )
        try writeFile(at: memoryDir.appendingPathComponent("feedback_use_pnpm.md"), contents: """
        ---
        name: Use pnpm
        description: prefer pnpm
        type: feedback
        ---
        """)

        let result = try MemoryScanner.scan(rootURL: root)
        #expect(result.count == 1)
        #expect(result.first?.name == "Use pnpm")
    }

    @Test func scan_ignoresNonMarkdownFiles() throws {
        let root = try makeFixture()
        defer { cleanup(root) }

        let memoryDir = root
            .appendingPathComponent("-Users-alice-project")
            .appendingPathComponent("memory")

        try writeFile(at: memoryDir.appendingPathComponent("notes.txt"), contents: "ignore me")
        try writeFile(at: memoryDir.appendingPathComponent("user_role.md"), contents: """
        ---
        name: Role
        description: data scientist
        type: user
        ---
        """)

        let result = try MemoryScanner.scan(rootURL: root)
        #expect(result.count == 1)
        #expect(result.first?.name == "Role")
    }

    @Test func scan_missingFrontmatter_fallsBackToFilenameAndPrefixType() throws {
        let root = try makeFixture()
        defer { cleanup(root) }

        let memoryFile = root
            .appendingPathComponent("-Users-alice-project")
            .appendingPathComponent("memory")
            .appendingPathComponent("reference_some_topic.md")

        try writeFile(at: memoryFile, contents: "Just plain markdown, no frontmatter.")

        let result = try MemoryScanner.scan(rootURL: root)
        let entry = try #require(result.first)
        #expect(entry.name == "reference some topic")
        #expect(entry.description == "")
        #expect(entry.type == .reference)
    }

    @Test func scan_typeFromFilename_whenFrontmatterOmitsType() throws {
        let root = try makeFixture()
        defer { cleanup(root) }

        let memoryFile = root
            .appendingPathComponent("-Users-alice-project")
            .appendingPathComponent("memory")
            .appendingPathComponent("project_auth_rewrite.md")

        try writeFile(at: memoryFile, contents: """
        ---
        name: Auth middleware rewrite
        description: legal-driven, not tech debt
        ---
        body
        """)

        let result = try MemoryScanner.scan(rootURL: root)
        let entry = try #require(result.first)
        #expect(entry.type == .project)
    }

    @Test func scan_aggregatesAcrossMultipleProjects() throws {
        let root = try makeFixture()
        defer { cleanup(root) }

        try writeFile(
            at: root.appendingPathComponent("-Users-alice-projectA")
                .appendingPathComponent("memory")
                .appendingPathComponent("user_role.md"),
            contents: "---\nname: A role\ndescription: a\ntype: user\n---"
        )
        try writeFile(
            at: root.appendingPathComponent("-Users-alice-projectB")
                .appendingPathComponent("memory")
                .appendingPathComponent("feedback_thing.md"),
            contents: "---\nname: B feedback\ndescription: b\ntype: feedback\n---"
        )

        let result = try MemoryScanner.scan(rootURL: root)
        #expect(result.count == 2)
        let names = Set(result.map(\.name))
        #expect(names == ["A role", "B feedback"])
    }
}
