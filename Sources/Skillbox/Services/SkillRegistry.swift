import Foundation
import Yams

struct RegistryEntry: Identifiable, Hashable {
    let path: String
    let name: String
    let description: String

    var id: String { path }
    var folderName: String { (path as NSString).lastPathComponent }
}

enum SkillRegistry {
    static let defaultRepo = "vercel-labs/agent-skills"
    static let defaultBranch = "main"
    static let defaultSkillsPath = "skills"

    enum RegistryError: LocalizedError {
        case badResponse(status: Int)
        case decoding(String)

        var errorDescription: String? {
            switch self {
            case .badResponse(let status): return "Registry request failed (HTTP \(status))"
            case .decoding(let msg): return "Could not parse registry response: \(msg)"
            }
        }
    }

    // MARK: - Public

    static func list(
        repo: String = defaultRepo,
        branch: String = defaultBranch,
        skillsPath: String = defaultSkillsPath,
        session: URLSession = .shared
    ) async throws -> [RegistryEntry] {
        let dirs = try await listDirectories(
            repo: repo,
            branch: branch,
            path: skillsPath,
            session: session
        )

        return try await withThrowingTaskGroup(of: RegistryEntry?.self) { group in
            for dir in dirs {
                group.addTask {
                    let skillPath = "\(dir.path)/SKILL.md"
                    do {
                        let md = try await fetchRaw(repo: repo, branch: branch, path: skillPath, session: session)
                        let (name, description) = parseFrontmatter(md, fallbackName: dir.name)
                        return RegistryEntry(path: dir.path, name: name, description: description)
                    } catch {
                        return nil
                    }
                }
            }
            var results: [RegistryEntry] = []
            for try await entry in group {
                if let entry { results.append(entry) }
            }
            return results.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    static func latestSHA(
        repo: String = defaultRepo,
        branch: String = defaultBranch,
        path: String,
        session: URLSession = .shared
    ) async throws -> String? {
        let url = URL(string: "https://api.github.com/repos/\(repo)/commits?path=\(path)&sha=\(branch)&per_page=1")!
        let data = try await fetchData(url: url, session: session)
        guard let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw RegistryError.decoding("commits response is not an array")
        }
        return array.first?["sha"] as? String
    }

    // MARK: - Internal helpers

    struct DirEntry {
        let name: String
        let path: String
    }

    static func listDirectories(
        repo: String,
        branch: String,
        path: String,
        session: URLSession
    ) async throws -> [DirEntry] {
        let url = URL(string: "https://api.github.com/repos/\(repo)/contents/\(path)?ref=\(branch)&per_page=100")!
        let data = try await fetchData(url: url, session: session)
        guard let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw RegistryError.decoding("contents response is not an array")
        }
        return array.compactMap { item in
            guard
                (item["type"] as? String) == "dir",
                let name = item["name"] as? String,
                let p = item["path"] as? String
            else { return nil }
            return DirEntry(name: name, path: p)
        }
    }

    private static func fetchRaw(
        repo: String,
        branch: String,
        path: String,
        session: URLSession
    ) async throws -> String {
        let url = URL(string: "https://raw.githubusercontent.com/\(repo)/\(branch)/\(path)")!
        let data = try await fetchData(url: url, session: session)
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func fetchData(url: URL, session: URLSession) async throws -> Data {
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("skillbox", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw RegistryError.badResponse(status: http.statusCode)
        }
        return data
    }

    static func parseFrontmatter(_ markdown: String, fallbackName: String) -> (name: String, description: String) {
        let lines = markdown.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            return (fallbackName, "")
        }
        var fmLines: [String] = []
        for line in lines.dropFirst() {
            if line.trimmingCharacters(in: .whitespaces) == "---" { break }
            fmLines.append(line)
        }
        let yaml = fmLines.joined(separator: "\n")
        guard let parsed = try? Yams.load(yaml: yaml) as? [String: Any] else {
            return (fallbackName, "")
        }
        let name = (parsed["name"] as? String) ?? fallbackName
        let description = (parsed["description"] as? String) ?? ""
        return (name, description)
    }
}
