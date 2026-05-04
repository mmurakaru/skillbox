import Foundation

struct SkillSourceCoordinates: Equatable {
    var repo: String     // "owner/repo"
    var branch: String   // "main"
    var path: String     // path within repo, e.g. "skills/find-skills"

    static func parse(provenance: SkillProvenance) -> SkillSourceCoordinates? {
        let raw = provenance.source.trimmingCharacters(in: .whitespaces)
        if raw.isEmpty { return nil }

        if let url = URL(string: raw),
           let host = url.host,
           host.contains("github.com") || host.contains("gitlab.com") {
            return parse(githubURL: url, fallbackSkill: provenance.skill, fallbackBranch: provenance.ref)
        }

        if isOwnerRepoShorthand(raw) {
            let path = provenance.skill.map { "\(SkillRegistry.defaultSkillsPath)/\($0)" } ?? SkillRegistry.defaultSkillsPath
            return SkillSourceCoordinates(repo: raw, branch: provenance.ref, path: path)
        }

        return nil
    }

    private static func isOwnerRepoShorthand(_ s: String) -> Bool {
        if s.contains("://") || s.hasPrefix("/") || s.hasPrefix(".") { return false }
        let parts = s.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        return parts.allSatisfy { !$0.isEmpty }
    }

    private static func parse(
        githubURL url: URL,
        fallbackSkill: String?,
        fallbackBranch: String
    ) -> SkillSourceCoordinates? {
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        let owner = parts[0]
        var repo = parts[1]
        if repo.hasSuffix(".git") { repo.removeLast(4) }
        let repoSlug = "\(owner)/\(repo)"

        if parts.count >= 4, parts[2] == "tree" {
            let branch = parts[3]
            let pathParts = Array(parts.dropFirst(4))
            let path: String
            if pathParts.isEmpty {
                path = fallbackSkill.map { "\(SkillRegistry.defaultSkillsPath)/\($0)" } ?? SkillRegistry.defaultSkillsPath
            } else {
                path = pathParts.joined(separator: "/")
            }
            return SkillSourceCoordinates(repo: repoSlug, branch: branch, path: path)
        }

        let path = fallbackSkill.map { "\(SkillRegistry.defaultSkillsPath)/\($0)" } ?? SkillRegistry.defaultSkillsPath
        return SkillSourceCoordinates(repo: repoSlug, branch: fallbackBranch, path: path)
    }
}
