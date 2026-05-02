import Testing
@testable import Skillbox

struct MemoryTypeTests {
    @Test func parse_user() { #expect(MemoryType.parse("user") == .user) }
    @Test func parse_feedback() { #expect(MemoryType.parse("feedback") == .feedback) }
    @Test func parse_project() { #expect(MemoryType.parse("project") == .project) }
    @Test func parse_reference() { #expect(MemoryType.parse("reference") == .reference) }

    @Test func parse_uppercaseInput_normalised() {
        #expect(MemoryType.parse("FEEDBACK") == .feedback)
        #expect(MemoryType.parse("Reference") == .reference)
    }

    @Test func parse_unknownString_returnsOther() {
        #expect(MemoryType.parse("unknown") == .other)
        #expect(MemoryType.parse("notes") == .other)
    }

    @Test func parse_nilOrEmpty_returnsOther() {
        #expect(MemoryType.parse(nil) == .other)
        #expect(MemoryType.parse("") == .other)
    }
}
