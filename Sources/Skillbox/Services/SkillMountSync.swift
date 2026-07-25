import Foundation

enum SkillMountSync {
    enum MountError: LocalizedError, Equatable {
        case sourceMissing(URL)
        case mountConflict(URL)

        var errorDescription: String? {
            switch self {
            case .sourceMissing(let url):
                return "Skill source does not exist: \(url.path)"
            case .mountConflict(let url):
                return "Claude skills mount already contains a real item: \(url.path)"
            }
        }
    }

    struct Report: Equatable {
        var created: [String] = []
        var repaired: [String] = []
        var unchanged: [String] = []
        var conflicts: [String] = []
    }

    @discardableResult
    static func ensureAll(sourceRootPath: String, mountRootPath: String) throws -> Report {
        let sourceRoot = URL(fileURLWithPath: (sourceRootPath as NSString).expandingTildeInPath)
        let mountRoot = URL(fileURLWithPath: (mountRootPath as NSString).expandingTildeInPath)
        return try ensureAll(sourceRoot: sourceRoot, mountRoot: mountRoot)
    }

    @discardableResult
    static func ensureAll(sourceRoot: URL, mountRoot: URL) throws -> Report {
        let fm = FileManager.default
        try fm.createDirectory(at: mountRoot, withIntermediateDirectories: true)

        let children = try fm.contentsOfDirectory(
            at: sourceRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        var report = Report()
        for source in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard (try? source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            guard fm.fileExists(atPath: source.appendingPathComponent("SKILL.md").path) else { continue }
            do {
                let outcome = try ensureMount(sourceURL: source, mountRoot: mountRoot)
                switch outcome {
                case .created: report.created.append(source.lastPathComponent)
                case .repaired: report.repaired.append(source.lastPathComponent)
                case .unchanged: report.unchanged.append(source.lastPathComponent)
                }
            } catch MountError.mountConflict {
                report.conflicts.append(source.lastPathComponent)
            }
        }
        return report
    }

    enum EnsureOutcome: Equatable {
        case created
        case repaired
        case unchanged
    }

    @discardableResult
    static func ensureMount(sourceURL: URL, mountRoot: URL) throws -> EnsureOutcome {
        let fm = FileManager.default
        guard fm.fileExists(atPath: sourceURL.appendingPathComponent("SKILL.md").path) else {
            throw MountError.sourceMissing(sourceURL)
        }
        try fm.createDirectory(at: mountRoot, withIntermediateDirectories: true)

        let linkURL = mountRoot.appendingPathComponent(sourceURL.lastPathComponent)
        let desiredTarget = sourceURL.path

        if isSymlink(linkURL) {
            let current = try? fm.destinationOfSymbolicLink(atPath: linkURL.path)
            let currentURL = current.map { URL(fileURLWithPath: $0, relativeTo: linkURL.deletingLastPathComponent()).standardizedFileURL }
            if currentURL?.resolvingSymlinksInPath().path == sourceURL.resolvingSymlinksInPath().path {
                return .unchanged
            }
            try fm.removeItem(at: linkURL)
            try fm.createSymbolicLink(atPath: linkURL.path, withDestinationPath: desiredTarget)
            return .repaired
        }

        if fm.fileExists(atPath: linkURL.path) {
            throw MountError.mountConflict(linkURL)
        }

        try fm.createSymbolicLink(atPath: linkURL.path, withDestinationPath: desiredTarget)
        return .created
    }

    static func removeMount(named name: String, mountRootPath: String) throws {
        let mountRoot = URL(fileURLWithPath: (mountRootPath as NSString).expandingTildeInPath)
        try removeMount(named: name, mountRoot: mountRoot)
    }

    static func removeMount(named name: String, mountRoot: URL) throws {
        let linkURL = mountRoot.appendingPathComponent(name)
        if isSymlink(linkURL) {
            try FileManager.default.removeItem(at: linkURL)
        }
    }

    static func isSymlink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }
}
