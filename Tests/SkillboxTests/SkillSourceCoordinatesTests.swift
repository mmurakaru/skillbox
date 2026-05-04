import Testing
@testable import Skillbox

struct SkillSourceCoordinatesTests {
    @Test func parse_ownerRepoShorthand_withSkill() {
        let provenance = SkillProvenance(
            source: "vercel-labs/agent-skills",
            skill: "frontend-design",
            ref: "main"
        )
        let coords = SkillSourceCoordinates.parse(provenance: provenance)
        #expect(coords == SkillSourceCoordinates(
            repo: "vercel-labs/agent-skills",
            branch: "main",
            path: "skills/frontend-design"
        ))
    }

    @Test func parse_ownerRepoShorthand_withoutSkill() {
        let provenance = SkillProvenance(source: "owner/repo", ref: "main")
        let coords = SkillSourceCoordinates.parse(provenance: provenance)
        #expect(coords?.repo == "owner/repo")
        #expect(coords?.path == "skills")
    }

    @Test func parse_githubTreeURL_withSubPath() {
        let provenance = SkillProvenance(
            source: "https://github.com/vercel-labs/agent-skills/tree/main/skills/frontend-design",
            ref: "main"
        )
        let coords = SkillSourceCoordinates.parse(provenance: provenance)
        #expect(coords == SkillSourceCoordinates(
            repo: "vercel-labs/agent-skills",
            branch: "main",
            path: "skills/frontend-design"
        ))
    }

    @Test func parse_githubURL_dotGitSuffixStripped() {
        let provenance = SkillProvenance(
            source: "https://github.com/owner/repo.git",
            skill: "foo",
            ref: "main"
        )
        let coords = SkillSourceCoordinates.parse(provenance: provenance)
        #expect(coords?.repo == "owner/repo")
        #expect(coords?.path == "skills/foo")
    }

    @Test func parse_returnsNilForUnsupportedSource() {
        let provenance = SkillProvenance(source: "/local/path", ref: "main")
        #expect(SkillSourceCoordinates.parse(provenance: provenance) == nil)
    }
}
