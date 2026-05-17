import Foundation

struct SkillProvenance: Codable, Hashable {
    static let sidecarFilename = ".skillbox.json"

    var source: String
    var skill: String?
    var ref: String
    var sha: String?
    var installedAt: Date
    var lastCheckedAt: Date?
    var latestKnownSHA: String?

    init(
        source: String,
        skill: String? = nil,
        ref: String = "main",
        sha: String? = nil,
        installedAt: Date = Date(),
        lastCheckedAt: Date? = nil,
        latestKnownSHA: String? = nil
    ) {
        self.source = source
        self.skill = skill
        self.ref = ref
        self.sha = sha
        self.installedAt = installedAt
        self.lastCheckedAt = lastCheckedAt
        self.latestKnownSHA = latestKnownSHA
    }

    var hasUpdate: Bool {
        guard let latest = latestKnownSHA, !latest.isEmpty else { return false }
        return latest != sha
    }
}

/// `provenance` is non-nil only for skills installed via `RemoteSkillService`
/// or adopted via the "Adopt as remote" action.
struct Skill: Identifiable, Hashable {
    let id: String
    let name: String
    let description: String
    let folderURL: URL
    let skillFileURL: URL
    let modifiedAt: Date
    let provenance: SkillProvenance?
    /// True when the skill's SKILL.md frontmatter sets `disable-model-invocation: true`.
    /// Surfaced as a read-only badge; `skillOverrides` still layers on top.
    let authorLocked: Bool

    init(
        name: String,
        description: String,
        folderURL: URL,
        modifiedAt: Date,
        provenance: SkillProvenance? = nil,
        authorLocked: Bool = false
    ) {
        self.id = folderURL.path
        self.name = name
        self.description = description
        self.folderURL = folderURL
        self.skillFileURL = folderURL.appendingPathComponent("SKILL.md")
        self.modifiedAt = modifiedAt
        self.provenance = provenance
        self.authorLocked = authorLocked
    }

    /// GitHub-style `@owner` derived from `provenance.source`, or `nil` for non-remote skills.
    var authorHandle: String? {
        guard let provenance,
              let coords = SkillSourceCoordinates.parse(provenance: provenance) else { return nil }
        return coords.repo.split(separator: "/").first.map(String.init)
    }
}

enum SkillProvenanceStore {
    static func read(from folderURL: URL) -> SkillProvenance? {
        let url = folderURL.appendingPathComponent(SkillProvenance.sidecarFilename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(SkillProvenance.self, from: data)
    }

    static func write(_ provenance: SkillProvenance, to folderURL: URL) throws {
        let url = folderURL.appendingPathComponent(SkillProvenance.sidecarFilename)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(provenance)
        try data.write(to: url, options: .atomic)
    }
}
