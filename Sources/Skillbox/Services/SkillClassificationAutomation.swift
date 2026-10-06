import Foundation
import Observation

/// Observes skill and credential changes without polling or repeating failed requests.
@MainActor
final class SkillClassificationAutomation {
    private let store: SkillStore
    private let classifications: SkillClassificationStore
    private let apiKey: () -> String
    private var lastAPIKey = ""
    private var attemptedDigests: [String: String] = [:]

    init(store: SkillStore, classifications: SkillClassificationStore, apiKey: @escaping () -> String) {
        self.store = store
        self.classifications = classifications
        self.apiKey = apiKey
        observeChanges()
    }

    private func observeChanges() {
        withObservationTracking {
            _ = store.items
            _ = apiKey()
            _ = classifications.isClassifying
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeChanges() }
        }
        classifyPendingSkills()
    }

    private func classifyPendingSkills() {
        let key = apiKey()
        if key != lastAPIKey {
            lastAPIKey = key
            attemptedDigests.removeAll()
            if classifications.isClassifying { classifications.cancelClassification() }
        }
        guard !key.isEmpty, !classifications.isClassifying else { return }
        var pending: [Skill] = []
        for skill in store.items {
            guard let content = try? String(contentsOf: skill.skillFileURL, encoding: .utf8) else { continue }
            let digest = SkillClassificationService.contentDigest(content)
            guard attemptedDigests[skill.id] != digest else { continue }
            if classifications.classification(for: skill)?.contentDigest == digest { continue }
            attemptedDigests[skill.id] = digest
            pending.append(skill)
        }
        if !pending.isEmpty { classifications.startClassification(skills: pending, apiKey: key) }
    }
}
