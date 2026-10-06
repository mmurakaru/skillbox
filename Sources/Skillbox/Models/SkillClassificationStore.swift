import Foundation
import Observation

/// Persists skill classifications locally and runs explicit, resumable classification batches.
@MainActor
@Observable
final class SkillClassificationStore {
    private(set) var classifications: [String: SkillClassification] = [:]
    private(set) var isClassifying = false
    private(set) var completedCount = 0
    private(set) var totalCount = 0
    private(set) var statusMessage: String?
    var selectedCategory = "all"
    var selectedActivity = "all"

    private let cacheURL: URL
    private let classify: (Skill, String, String) async throws -> SkillClassification
    private var classificationTask: Task<Void, Never>?

    init(
        cacheURL: URL = URL.applicationSupportDirectory.appendingPathComponent("Skillbox/classifications.json"),
        classify: @escaping (Skill, String, String) async throws -> SkillClassification = {
            try await SkillClassificationService().classifySkill($0, content: $1, apiKey: $2)
        }
    ) {
        self.cacheURL = cacheURL
        self.classify = classify
        if FileManager.default.fileExists(atPath: cacheURL.path) {
            do { classifications = try JSONDecoder().decode([String: SkillClassification].self, from: Data(contentsOf: cacheURL)) }
            catch { statusMessage = "Could not read saved classifications: \(error.localizedDescription)" }
        }
    }

    func classification(for skill: Skill) -> SkillClassification? {
        guard let result = classifications[skill.id], result.matches(skill) else { return nil }
        return result
    }

    /// Applies category and activity filters to the already search-filtered skill list.
    func filteredSkills(_ skills: [Skill]) -> [Skill] {
        skills.filter { skill in
            let result = classification(for: skill)
            let matchesCategory = selectedCategory == "all" ||
                (selectedCategory == "unclassified" && (result?.categories.isEmpty ?? true)) ||
                (result?.categories.contains(where: { $0.rawValue == selectedCategory }) ?? false)
            let matchesActivity = selectedActivity == "all" ||
                (selectedActivity == "unclassified" && result?.activity == nil) ||
                result?.activity?.rawValue == selectedActivity
            return matchesCategory && matchesActivity
        }
    }

    func startClassification(skills: [Skill], apiKey: String, force: Bool = false) {
        guard !isClassifying else { return }
        guard !apiKey.isEmpty else {
            statusMessage = SkillClassificationError.missingAPIKey.localizedDescription
            return
        }
        isClassifying = true
        completedCount = 0
        totalCount = skills.count
        statusMessage = nil
        classificationTask = Task {
            defer { isClassifying = false; classificationTask = nil }
            var classified = 0
            var skipped = 0
            var failed = 0
            var firstError: String?
            for skill in skills {
                if Task.isCancelled { break }
                do {
                    let content = try String(contentsOf: skill.skillFileURL, encoding: .utf8)
                    if !force, let saved = classification(for: skill),
                       saved.contentDigest == SkillClassificationService.contentDigest(content) {
                        skipped += 1
                    } else {
                        let result = try await classify(skill, content, apiKey)
                        try Task.checkCancellation()
                        // Never overwrite a cache with labels for a file edited during a request.
                        let current = try String(contentsOf: skill.skillFileURL, encoding: .utf8)
                        guard SkillClassificationService.contentDigest(current) == result.contentDigest else {
                            throw NSError(domain: "SkillClassificationStore", code: 1, userInfo: [
                                NSLocalizedDescriptionKey: "\(skill.name) changed during classification. Run Classify again.",
                            ])
                        }
                        var updated = classifications
                        updated[skill.id] = result
                        try saveClassifications(updated)
                        classifications = updated
                        classified += 1
                    }
                } catch is CancellationError { break }
                catch {
                    failed += 1
                    firstError = firstError ?? error.localizedDescription
                    // Stop on API-wide failures instead of repeating rejected requests for every skill.
                    if let apiError = error as? SkillClassificationError,
                       case .httpStatus(let code) = apiError, [401, 403, 429].contains(code) {
                        completedCount += 1
                        break
                    }
                }
                completedCount += 1
            }
            statusMessage = "\(classified) classified, \(skipped) unchanged" +
                (failed > 0 ? ". \(failed) failed: \(firstError ?? "Unknown error")" : "") +
                (Task.isCancelled ? ". Cancelled." : "")
        }
    }

    func cancelClassification() { classificationTask?.cancel() }

    private func saveClassifications(_ values: [String: SkillClassification]) throws {
        try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(values).write(to: cacheURL, options: .atomic)
    }
}
