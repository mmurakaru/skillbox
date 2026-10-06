import Foundation

/// Categories describe a skill's subject; a skill can belong to several.
enum SkillCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case engineering, productivity, design, writing, research, other

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    var criteria: String {
        switch self {
        case .engineering: "Software development, testing, debugging, architecture, infrastructure, or planning software work."
        case .productivity: "General workflow organization, task management, handoffs, interviews, or learning usable outside software development."
        case .design: "Visual design, user experience, interfaces, illustrations, or other visual artifacts."
        case .writing: "Authoring, editing, or improving prose, documentation, or communication."
        case .research: "Investigating questions by collecting, verifying, or comparing evidence and sources."
        case .other: "A subject outside engineering, productivity, design, writing, and research."
        }
    }
}

/// Activities describe the main action performed by a skill, independently of category.
enum SkillActivity: String, Codable, CaseIterable, Identifiable, Sendable {
    case planning, building, debugging, reviewing, researching, writing, learning, setup, other

    var id: String { rawValue }
    var label: String { rawValue == "setup" ? "Setup" : rawValue.capitalized }

    var criteria: String {
        switch self {
        case .planning: "Clarify goals, make decisions, design an approach, or produce specs, plans, and tickets before execution."
        case .building: "Implement or change working software, including test-driven development."
        case .debugging: "Reproduce, diagnose, or fix a bug, failure, or performance regression."
        case .reviewing: "Assess existing work against requirements or standards and report findings."
        case .researching: "Gather and verify evidence from sources to answer a question."
        case .writing: "Create, edit, or explain text, documentation, or a handoff."
        case .learning: "Teach, coach, or practice a skill or concept."
        case .setup: "Install, configure, provision, or manage tools, services, and environments."
        case .other: "An activity outside the listed options, such as creating an image."
        }
    }
}

/// Cached classification is valid only for the same skill revision and taxonomy.
struct SkillClassification: Codable, Sendable {
    static let taxonomyVersion = 1
    var categories: [SkillCategory]
    var activity: SkillActivity?
    var modifiedAt: Date
    var contentDigest: String
    var model: String
    var version: Int = taxonomyVersion

    func matches(_ skill: Skill) -> Bool {
        version == Self.taxonomyVersion && modifiedAt == skill.modifiedAt
    }
}
