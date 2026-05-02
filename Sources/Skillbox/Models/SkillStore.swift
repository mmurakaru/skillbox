import Foundation
import Observation

@MainActor
@Observable
final class SkillStore {
    private(set) var skills: [Skill] = []
    private(set) var lastError: String?

    var searchQuery: String = ""

    private var watcher: DirectoryWatcher?
    private var rootPath: String = ""

    var filteredSkills: [Skill] {
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return skills }
        return skills.filter { skill in
            skill.name.localizedCaseInsensitiveContains(query) ||
            skill.description.localizedCaseInsensitiveContains(query)
        }
    }

    func configure(rootPath: String) {
        let expanded = (rootPath as NSString).expandingTildeInPath
        if expanded == self.rootPath { return }
        self.rootPath = expanded
        rescan()
        startWatching()
    }

    func rescan() {
        let url = URL(fileURLWithPath: rootPath)
        do {
            skills = try SkillScanner.scan(rootURL: url)
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            lastError = nil
        } catch {
            skills = []
            lastError = "Failed to scan \(rootPath): \(error.localizedDescription)"
        }
    }

    func remove(_ skill: Skill) {
        skills.removeAll { $0.id == skill.id }
    }

    private func startWatching() {
        watcher = nil
        let url = URL(fileURLWithPath: rootPath)
        watcher = DirectoryWatcher(url: url) { [weak self] in
            Task { @MainActor in self?.rescan() }
        }
    }
}
