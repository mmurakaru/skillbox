import Testing
@testable import Skillbox

struct SkillsCLITests {
    @Test func addArgs_withoutSkill() {
        let opts = SkillsCLI.InstallOptions(source: "vercel-labs/agent-skills")
        #expect(SkillsCLI.addArgs(for: opts) == [
            "add", "vercel-labs/agent-skills",
            "-a", "claude-code",
            "-g", "--copy", "-y"
        ])
    }

    @Test func addArgs_withSkill() {
        let opts = SkillsCLI.InstallOptions(
            source: "vercel-labs/agent-skills",
            skill: "frontend-design"
        )
        #expect(SkillsCLI.addArgs(for: opts) == [
            "add", "vercel-labs/agent-skills",
            "--skill", "frontend-design",
            "-a", "claude-code",
            "-g", "--copy", "-y"
        ])
    }

    @Test func addArgs_skipsCopyWhenDisabled() {
        let opts = SkillsCLI.InstallOptions(
            source: "owner/repo",
            global: false,
            copyMode: false
        )
        #expect(SkillsCLI.addArgs(for: opts) == [
            "add", "owner/repo",
            "-a", "claude-code",
            "-y"
        ])
    }

    @Test func updateArgs() {
        #expect(SkillsCLI.updateArgs(skillName: "find-skills") == [
            "update", "find-skills", "-a", "claude-code", "-g", "-y"
        ])
    }

    @Test func removeArgs() {
        #expect(SkillsCLI.removeArgs(skillName: "find-skills") == [
            "remove", "find-skills", "-a", "claude-code", "-g", "-y"
        ])
    }

    @Test func shellQuote_leavesSafeCharsAlone() {
        #expect(SkillsCLI.shellQuote("vercel-labs/agent-skills") == "vercel-labs/agent-skills")
        #expect(SkillsCLI.shellQuote("--skill") == "--skill")
        #expect(SkillsCLI.shellQuote("path/to/thing.tar.gz") == "path/to/thing.tar.gz")
    }

    @Test func shellQuote_quotesSpacesAndShellMeta() {
        #expect(SkillsCLI.shellQuote("a b") == "'a b'")
        #expect(SkillsCLI.shellQuote("a$b") == "'a$b'")
        #expect(SkillsCLI.shellQuote("a;b") == "'a;b'")
    }

    @Test func shellQuote_escapesEmbeddedSingleQuote() {
        #expect(SkillsCLI.shellQuote("Mary's skill") == "'Mary'\\''s skill'")
    }

    @Test func shellQuote_emptyStringIsTwoQuotes() {
        #expect(SkillsCLI.shellQuote("") == "''")
    }
}
