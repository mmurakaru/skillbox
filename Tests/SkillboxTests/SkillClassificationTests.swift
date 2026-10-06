import Foundation
import Testing
@testable import Skillbox

@MainActor
struct SkillClassificationTests {
    private func skill(_ name: String = "wayfinder", root: URL = URL(fileURLWithPath: "/tmp/skills"), date: Date = Date(timeIntervalSince1970: 100)) -> Skill {
        Skill(name: name, description: "Plan large software projects", folderURL: root.appendingPathComponent(name), modifiedAt: date)
    }

    private func response(categoryProbability: Double = 0.95, confidence: Double = 0.9) throws -> Data {
        var answers: [String: Any] = [:]
        for category in SkillCategory.allCases {
            answers[category.rawValue] = ["type": "noul", "noul": category == .engineering || category == .productivity ? categoryProbability : 0.1]
        }
        answers["activity"] = [
            "type": "choice", "choice": "planning", "confidence": confidence,
            "probabilities": Dictionary(uniqueKeysWithValues: SkillActivity.allCases.map { ($0.rawValue, $0 == .planning ? 1.0 : 0.0) }),
        ]
        return try JSONSerialization.data(withJSONObject: ["model": "jev-1.13.0", "answers": answers])
    }

    @Test func requestSendsFullSkillAndSeparateSubjectAndActivityQuestions() throws {
        let data = try SkillClassificationService.requestBody(skill: skill(), content: "Full skill instructions")
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let state = try #require(body["state"] as? [String: String])
        #expect(state["skill_markdown"] == "Full skill instructions")
        #expect(body["model"] as? String == "jev-latest")
        let questions = try #require(body["questions"] as? [String: [String: Any]])
        #expect(questions["engineering"]?["type"] as? String == "noul")
        #expect(questions["activity"]?["type"] as? String == "choice")
        #expect(questions.count == SkillCategory.allCases.count + 1)
    }

    @Test func responseSupportsMultipleCategoriesAndOneActivity() throws {
        let result = try SkillClassificationService.parseClassification(response(), skill: skill(), content: "plan")
        #expect(result.categories == [.engineering, .productivity])
        #expect(result.activity == .planning)
        #expect(result.model == "jev-1.13.0")
    }

    @Test func uncertainAnswersRemainUnclassified() throws {
        let result = try SkillClassificationService.parseClassification(response(categoryProbability: 0.5, confidence: 0.3), skill: skill(), content: "plan")
        #expect(result.categories.isEmpty)
        #expect(result.activity == nil)
    }

    @Test func malformedResponseCannotBecomeCachedLabels() throws {
        #expect(throws: SkillClassificationError.self) {
            try SkillClassificationService.parseClassification(Data("{}".utf8), skill: skill(), content: "plan")
        }
        let data = try response(categoryProbability: 1.2)
        #expect(throws: SkillClassificationError.self) {
            try SkillClassificationService.parseClassification(data, skill: skill(), content: "plan")
        }
    }

    @Test func rejectedAPIKeyReturnsActionableError() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RejectedTypeSafeRequest.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        do {
            _ = try await SkillClassificationService(session: session).classifySkill(skill(), content: "plan", apiKey: "test-key")
            Issue.record("Expected authentication failure")
        } catch {
            #expect(error.localizedDescription == "TypeSafe rejected the API key. Check it in Settings.")
        }
    }

    private func temporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("skillbox-classification-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func writeSkill(_ skill: Skill, content: String = "plan") throws {
        try FileManager.default.createDirectory(at: skill.folderURL, withIntermediateDirectories: true)
        try content.write(to: skill.skillFileURL, atomically: true, encoding: .utf8)
    }

    private func waitForClassification(_ store: SkillClassificationStore) async throws {
        for _ in 0..<200 {
            if !store.isClassifying { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("Classification did not finish")
    }

    @Test func cacheSurvivesRelaunchAndFiltersCombineWithSearch() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let planned = skill(root: root)
        let unknown = skill("unknown", root: root)
        try writeSkill(planned)
        let data = try response()
        let cache = root.appendingPathComponent("cache.json")
        let store = SkillClassificationStore(cacheURL: cache) { skill, content, _ in
            try SkillClassificationService.parseClassification(data, skill: skill, content: content)
        }
        store.startClassification(skills: [planned], apiKey: "test-key")
        try await waitForClassification(store)
        let restored = SkillClassificationStore(cacheURL: cache)
        restored.selectedCategory = "engineering"
        restored.selectedActivity = "planning"
        #expect(restored.filteredSkills([planned, unknown]).map(\.name) == ["wayfinder"])
        let skills = SkillStore(seedSkills: [planned, unknown])
        skills.searchQuery = "unknown"
        #expect(restored.filteredSkills(skills.filteredItems).isEmpty)
        restored.selectedCategory = "unclassified"
        restored.selectedActivity = "all"
        #expect(restored.filteredSkills([planned, unknown]).map(\.name) == ["unknown"])
        let changed = skill(root: root, date: Date(timeIntervalSince1970: 200))
        #expect(restored.classification(for: changed) == nil)
    }

    @Test func unchangedSkillsAreSkippedButForceAndChangedContentRunAgain() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let item = skill(root: root)
        try writeSkill(item)
        var calls = 0
        let data = try response()
        let store = SkillClassificationStore(cacheURL: root.appendingPathComponent("cache.json")) { skill, content, _ in
            calls += 1
            return try SkillClassificationService.parseClassification(data, skill: skill, content: content)
        }
        for force in [false, false, true] {
            store.startClassification(skills: [item], apiKey: "test-key", force: force)
            try await waitForClassification(store)
        }
        #expect(calls == 2)
        try writeSkill(item, content: "changed")
        store.startClassification(skills: [item], apiKey: "test-key")
        try await waitForClassification(store)
        #expect(calls == 3)
    }

    @Test func failurePreservesSuccessfulResultsAndAuthenticationFailureStopsBatch() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let items = [skill("good", root: root), skill("bad", root: root), skill("later", root: root)]
        for item in items { try writeSkill(item) }
        var calls = 0
        let data = try response()
        let store = SkillClassificationStore(cacheURL: root.appendingPathComponent("cache.json")) { skill, content, _ in
            calls += 1
            if skill.name == "bad" { throw SkillClassificationError.httpStatus(401) }
            return try SkillClassificationService.parseClassification(data, skill: skill, content: content)
        }
        store.startClassification(skills: items, apiKey: "test-key")
        try await waitForClassification(store)
        #expect(calls == 2)
        #expect(store.classification(for: items[0]) != nil)
        #expect(store.classification(for: items[1]) == nil)
        #expect(store.statusMessage?.contains("Check it in Settings") == true)
        #expect(store.hasClassificationFailure)
        store.startClassification(skills: [items[0]], apiKey: "test-key")
        #expect(!store.hasClassificationFailure)
        try await waitForClassification(store)
        #expect(!store.hasClassificationFailure)
    }

    @Test func cancellationKeepsPreviousResultsAndNeverStartsRemainingRequests() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let items = [skill("first", root: root), skill("second", root: root), skill("third", root: root)]
        for item in items { try writeSkill(item) }
        var calls = 0
        let data = try response()
        let store = SkillClassificationStore(cacheURL: root.appendingPathComponent("cache.json")) { skill, content, _ in
            calls += 1
            if calls == 2 {
                do { try await Task.sleep(for: .seconds(30)) }
                catch { throw URLError(.cancelled) }
            }
            return try SkillClassificationService.parseClassification(data, skill: skill, content: content)
        }
        store.startClassification(skills: items, apiKey: "test-key")
        while calls < 2 { try await Task.sleep(for: .milliseconds(5)) }
        store.cancelClassification()
        try await waitForClassification(store)
        #expect(calls == 2)
        #expect(store.classification(for: items[0]) != nil)
        #expect(store.classification(for: items[1]) == nil)
        #expect(store.statusMessage?.contains("Cancelled") == true)
        #expect(!store.hasClassificationFailure)
    }
}

private final class RejectedTypeSafeRequest: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        #expect(request.url?.absoluteString == "https://api.typesafe.ai/v1/systemone")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
        let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
