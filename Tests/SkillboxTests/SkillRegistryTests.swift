import Testing
@testable import Skillbox

struct SkillRegistryTests {
    @Test func parseFrontmatter_extractsNameAndDescription() {
        let md = """
        ---
        name: frontend-design
        description: Builds production-grade frontend interfaces.
        ---

        body
        """
        let (name, desc) = SkillRegistry.parseFrontmatter(md, fallbackName: "fallback")
        #expect(name == "frontend-design")
        #expect(desc == "Builds production-grade frontend interfaces.")
    }

    @Test func parseFrontmatter_fallsBackWhenMissing() {
        let md = "no frontmatter here"
        let (name, desc) = SkillRegistry.parseFrontmatter(md, fallbackName: "my-skill")
        #expect(name == "my-skill")
        #expect(desc == "")
    }

    @Test func parseFrontmatter_fallsBackWhenNameMissing() {
        let md = """
        ---
        description: only description
        ---
        """
        let (name, desc) = SkillRegistry.parseFrontmatter(md, fallbackName: "fallback")
        #expect(name == "fallback")
        #expect(desc == "only description")
    }

    @Test func parseFrontmatter_handlesEmptyDescription() {
        let md = """
        ---
        name: x
        ---
        """
        let (name, desc) = SkillRegistry.parseFrontmatter(md, fallbackName: "fallback")
        #expect(name == "x")
        #expect(desc == "")
    }
}
