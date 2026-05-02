import Testing
import Foundation
@testable import Skillbox

struct SkillCreatorTests {
    private func makeFixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("skillbox-creator-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - sanitize

    @Test func sanitize_lowercasesInput() {
        #expect(SkillCreator.sanitize("MySkill") == "myskill")
    }

    @Test func sanitize_replacesSpacesWithHyphens() {
        #expect(SkillCreator.sanitize("my skill name") == "my-skill-name")
    }

    @Test func sanitize_replacesPunctuationWithHyphens() {
        #expect(SkillCreator.sanitize("hello.world!") == "hello-world")
    }

    @Test func sanitize_collapsesConsecutiveHyphens() {
        #expect(SkillCreator.sanitize("foo - - bar") == "foo-bar")
    }

    @Test func sanitize_trimsLeadingAndTrailingHyphens() {
        #expect(SkillCreator.sanitize("---foo---") == "foo")
    }

    @Test func sanitize_keepsDigitsAndExistingHyphens() {
        #expect(SkillCreator.sanitize("api-v2-handler") == "api-v2-handler")
    }

    // MARK: - isValidName

    @Test func isValidName_acceptsKebabCaseLowercase() {
        #expect(SkillCreator.isValidName("my-skill"))
        #expect(SkillCreator.isValidName("api-v2"))
    }

    @Test func isValidName_rejectsEmpty() {
        #expect(!SkillCreator.isValidName(""))
    }

    @Test func isValidName_rejectsUppercase() {
        #expect(!SkillCreator.isValidName("MySkill"))
    }

    @Test func isValidName_rejectsPunctuation() {
        #expect(!SkillCreator.isValidName("my.skill"))
        #expect(!SkillCreator.isValidName("my_skill"))
        #expect(!SkillCreator.isValidName("my skill"))
    }

    // MARK: - create

    @Test func create_writesFolderAndSkillMd() throws {
        let root = try makeFixture()
        defer { cleanup(root) }

        let result = SkillCreator.create(name: "my-skill", in: root.path)
        let folder = try #require(try? result.get())
        #expect(folder.lastPathComponent == "my-skill")

        let skillFile = folder.appendingPathComponent("SKILL.md")
        #expect(FileManager.default.fileExists(atPath: skillFile.path))
        let contents = try String(contentsOf: skillFile, encoding: .utf8)
        #expect(contents.contains("name: my-skill"))
        #expect(contents.hasPrefix("---"))
    }

    @Test func create_invalidName_returnsInvalidNameError() throws {
        let root = try makeFixture()
        defer { cleanup(root) }

        let result = SkillCreator.create(name: "Invalid Name", in: root.path)
        switch result {
        case .failure(.invalidName): break
        default: Issue.record("expected .invalidName, got \(result)")
        }
    }

    @Test func create_alreadyExists_returnsAlreadyExistsError() throws {
        let root = try makeFixture()
        defer { cleanup(root) }

        _ = SkillCreator.create(name: "duplicate", in: root.path)
        let result = SkillCreator.create(name: "duplicate", in: root.path)

        switch result {
        case .failure(.alreadyExists(let url)):
            #expect(url.lastPathComponent == "duplicate")
        default:
            Issue.record("expected .alreadyExists, got \(result)")
        }
    }
}
