import Foundation

enum MemoryType: String, CaseIterable {
    case user
    case feedback
    case project
    case reference
    case other

    var displayName: String {
        switch self {
        case .user: "user"
        case .feedback: "feedback"
        case .project: "project"
        case .reference: "reference"
        case .other: "other"
        }
    }

    var shortLabel: String {
        switch self {
        case .user: "user"
        case .feedback: "feedback"
        case .project: "project"
        case .reference: "reference"
        case .other: "other"
        }
    }

    static func parse(_ raw: String?) -> MemoryType {
        guard let raw = raw?.lowercased() else { return .other }
        return MemoryType(rawValue: raw) ?? .other
    }
}

struct Memory: Identifiable, Hashable {
    let id: String
    let name: String
    let description: String
    let type: MemoryType
    let fileURL: URL
    let projectFolderURL: URL
    let projectDisplayName: String
    let projectFullPath: String
    let modifiedAt: Date

    init(
        name: String,
        description: String,
        type: MemoryType,
        fileURL: URL,
        projectFolderURL: URL,
        modifiedAt: Date
    ) {
        self.id = fileURL.path
        self.name = name
        self.description = description
        self.type = type
        self.fileURL = fileURL
        self.projectFolderURL = projectFolderURL
        let decoded = Self.decodeProjectPath(projectFolderURL.lastPathComponent)
        self.projectDisplayName = decoded.last
        self.projectFullPath = decoded.full
        self.modifiedAt = modifiedAt
    }

    static func decodeProjectPath(
        _ encoded: String,
        validator: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> (full: String, last: String) {
        let trimmed = encoded.hasPrefix("-") ? String(encoded.dropFirst()) : encoded
        let parts = trimmed.split(separator: "-").map(String.init)

        if let resolved = resolveAgainstFilesystem(parts: parts, base: "", validator: validator) {
            let last = (resolved as NSString).lastPathComponent
            return (resolved, last)
        }

        let full = "/" + parts.joined(separator: "/")
        let last = parts.last ?? encoded
        return (full, last)
    }

    private static func resolveAgainstFilesystem(
        parts: [String],
        base: String,
        validator: (String) -> Bool
    ) -> String? {
        if parts.isEmpty { return base.isEmpty ? nil : base }

        // Try the longest contiguous prefix first; for each, try both `-` and `.`
        // as the separator (since the encoding loses both `/` and `.`).
        for prefixLen in stride(from: parts.count, to: 0, by: -1) {
            let prefix = parts[0..<prefixLen]
            for sep in ["-", "."] {
                let candidate = prefix.joined(separator: sep)
                let trial = base + "/" + candidate
                guard validator(trial) else { continue }

                let remaining = Array(parts[prefixLen...])
                if remaining.isEmpty { return trial }
                if let result = resolveAgainstFilesystem(parts: remaining, base: trial, validator: validator) {
                    return result
                }
            }
        }
        return nil
    }
}
