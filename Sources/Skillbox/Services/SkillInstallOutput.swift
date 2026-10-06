import Foundation

/// Translates terminal output into stable UI statuses, including output split across pipe chunks.
struct SkillInstallOutput {
    private var buffer = ""
    private(set) var stage: SkillInstallStage = .downloading

    mutating func append(_ chunk: String) {
        buffer = String((buffer + chunk).suffix(16_384))
        let text = Self.plainText(buffer).lowercased()
        if text.contains("installation complete") || text.contains("installed successfully") {
            stage = .finishing
        } else if text.contains("installing") || text.contains("installation summary") {
            stage = .installing
        } else if text.contains("found") && text.contains("skill") || text.contains("discovering") {
            stage = .finding
        }
    }

    static func plainText(_ output: String) -> String {
        output.replacingOccurrences(of: "\u{1B}\\][^\u{7}\u{1B}]*(?:\u{7}|\u{1B}\\\\)", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\u{1B}\\[[0-?]*[ -/]*[@-~]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\r", with: "\n")
            .unicodeScalars.filter { $0.value >= 32 || $0 == "\n" || $0 == "\t" }
            .map(String.init).joined()
    }

    static func failureMessage(output: String, exitCode: Int32) -> String {
        let lines = plainText(output).components(separatedBy: "\n")
        let reason = lines.first { line in
            let text = line.lowercased()
            return text.contains("fatal:") || text.contains("error:") || text.contains("no skills found") || text.contains("npm error")
        }?.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "│┃◇■└┌")))
        if let reason, !reason.isEmpty { return "Could not install the skill. \(String(reason.prefix(240)))" }
        return "Could not install the skill (exit \(exitCode)). Check the URL and your network connection, then try again."
    }

    static func installedNames(output: String) -> [String] {
        let text = plainText(output)
        let pattern = #"(?:~|/[^\s│]+)/(?:\.agents|\.claude)/skills/([A-Za-z0-9][A-Za-z0-9._-]*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        var names: [String] = []
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range(at: 1), in: text) else { continue }
            let name = String(text[range])
            if !names.contains(name) { names.append(name) }
        }
        return names
    }
}

enum SkillInstallStage: Int, CaseIterable {
    case downloading, finding, installing, finishing

    var label: String {
        switch self {
        case .downloading: "Download repository"
        case .finding: "Find skill files"
        case .installing: "Install skills"
        case .finishing: "Set up skill access"
        }
    }
}
