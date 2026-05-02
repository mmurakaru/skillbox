import Testing
@testable import Skillbox

struct MemoryDecodeTests {
    private func validator(existing: Set<String>) -> (String) -> Bool {
        { existing.contains($0) }
    }

    @Test func simpleSegments_returnsLastAsDisplayName() {
        let existing: Set<String> = [
            "/Users",
            "/Users/alice",
            "/Users/alice/projects",
            "/Users/alice/projects/widget",
        ]
        let result = Memory.decodeProjectPath(
            "-Users-alice-projects-widget",
            validator: validator(existing: existing)
        )
        #expect(result.full == "/Users/alice/projects/widget")
        #expect(result.last == "widget")
    }

    @Test func lastSegmentHasHyphen_resolvesCorrectly() {
        let existing: Set<String> = [
            "/Users",
            "/Users/alice",
            "/Users/alice/projects",
            "/Users/alice/projects/multi-word-project",
        ]
        let result = Memory.decodeProjectPath(
            "-Users-alice-projects-multi-word-project",
            validator: validator(existing: existing)
        )
        #expect(result.full == "/Users/alice/projects/multi-word-project")
        #expect(result.last == "multi-word-project")
    }

    @Test func usernameHasDot_resolvesCorrectly() {
        let existing: Set<String> = [
            "/Users",
            "/Users/alice.example",
            "/Users/alice.example/projects",
            "/Users/alice.example/projects/widget",
        ]
        let result = Memory.decodeProjectPath(
            "-Users-alice-example-projects-widget",
            validator: validator(existing: existing)
        )
        #expect(result.full == "/Users/alice.example/projects/widget")
        #expect(result.last == "widget")
    }

    @Test func dotInUsernameAndHyphenInProject_resolvesCorrectly() {
        let existing: Set<String> = [
            "/Users",
            "/Users/alice.example",
            "/Users/alice.example/projects",
            "/Users/alice.example/projects/multi-word-project",
        ]
        let result = Memory.decodeProjectPath(
            "-Users-alice-example-projects-multi-word-project",
            validator: validator(existing: existing)
        )
        #expect(result.full == "/Users/alice.example/projects/multi-word-project")
        #expect(result.last == "multi-word-project")
    }

    @Test func unresolvable_fallsBackToNaiveDecoding() {
        let result = Memory.decodeProjectPath(
            "-this-path-does-not-exist-on-disk",
            validator: { _ in false }
        )
        #expect(result.full == "/this/path/does/not/exist/on/disk")
        #expect(result.last == "disk")
    }
}
