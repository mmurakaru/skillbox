import Foundation
import Testing
@testable import Skillbox

@MainActor
struct DirectoryWatcherTests {
    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(condition())
    }

    @Test func recursiveWatcherDetectsNestedEditsAtomicReplacementsAndNewDirectories() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("skillbox-watcher-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let nested = root.appendingPathComponent("nested/skill")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let file = nested.appendingPathComponent("SKILL.md")
        try "original".write(to: file, atomically: true, encoding: .utf8)
        var changes = 0
        let watcher = try #require(DirectoryWatcher(url: root) { changes += 1 })
        defer { withExtendedLifetime(watcher) {} }
        try "edited".write(to: file, atomically: false, encoding: .utf8)
        try await waitUntil { changes > 0 }
        let prior = changes
        try "replaced".write(to: file, atomically: true, encoding: .utf8)
        try await waitUntil { changes > prior }
        let previous = changes
        try FileManager.default.createDirectory(at: root.appendingPathComponent("new/skill"), withIntermediateDirectories: true)
        try await waitUntil { changes > previous }
    }

    @Test func missingRootAppearsAndLinkedSkillEditsRefreshStoreAutomatically() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("skillbox-watchstore-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("external/linked")
        let skills = root.appendingPathComponent("skills")
        let store = SkillStore()
        store.configure(rootPath: skills.path)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: skills, withIntermediateDirectories: true)
        let file = source.appendingPathComponent("SKILL.md")
        try "---\nname: original\ndescription: test\n---".write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: skills.appendingPathComponent("linked"), withDestinationURL: source)
        try await waitUntil { store.items.first?.name == "original" }
        try "---\nname: changed\ndescription: test\n---".write(to: file, atomically: true, encoding: .utf8)
        try await waitUntil { store.items.first?.name == "changed" }
    }

    @Test func pathFilterIgnoresUnrelatedConversationLogs() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("skillbox-watchfilter-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var changes = 0
        let watcher = try #require(DirectoryWatcher(url: root, acceptsPath: { $0.hasSuffix("settings.json") }) { changes += 1 })
        defer { withExtendedLifetime(watcher) {} }
        try "log".write(to: root.appendingPathComponent("conversation.jsonl"), atomically: true, encoding: .utf8)
        try "{}".write(to: root.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
        try await waitUntil { changes > 0 }
        let before = changes
        try "more logs".write(to: root.appendingPathComponent("conversation.jsonl"), atomically: true, encoding: .utf8)
        try await Task.sleep(for: .seconds(1))
        #expect(changes == before)
    }

    @Test func withoutAncestorFallbackOnlyExistingFoldersAreWatched() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("skillbox-roots-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let existing = root.appendingPathComponent("existing")
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)
        let missing = root.appendingPathComponent("missing/models")

        let watcher = try #require(DirectoryWatcher(urls: [existing, missing], watchesMissingPathsThroughAncestors: false) {})
        #expect(watcher.streamRootPaths == [existing.resolvingSymlinksInPath().path])
        #expect(DirectoryWatcher(urls: [missing], watchesMissingPathsThroughAncestors: false) {} == nil)
    }

    @Test func releasingWatchersWhileEventsArriveOffMainWaitsForInFlightCallbacks() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("skillbox-watchrelease-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let eventQueue = DispatchQueue(label: "watcher-release-test", qos: .utility)
        let writer = Task.detached {
            var index = 0
            while !Task.isCancelled {
                try? "\(index)".write(to: root.appendingPathComponent("file-\(index % 8).txt"), atomically: true, encoding: .utf8)
                index += 1
            }
        }
        defer { writer.cancel() }

        for _ in 0..<40 {
            var watcher = DirectoryWatcher(urls: [root], eventQueue: eventQueue, acceptsPath: { _ in Thread.sleep(forTimeInterval: 0.002); return true }) {}
            #expect(watcher != nil)
            try await Task.sleep(for: .milliseconds(15))
            watcher = nil
        }
    }

    @Test func eventsOnAPrivateQueueStillCallBackOnTheMainThread() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("skillbox-queue-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var callbacksOnMainThread: [Bool] = []
        let watcher = try #require(DirectoryWatcher(urls: [root], eventQueue: DispatchQueue(label: "test-watcher")) {
            callbacksOnMainThread.append(Thread.isMainThread)
        })
        defer { withExtendedLifetime(watcher) {} }

        try "change".write(to: root.appendingPathComponent("model.gguf"), atomically: true, encoding: .utf8)

        try await waitUntil { !callbacksOnMainThread.isEmpty }
        #expect(callbacksOnMainThread.allSatisfy { $0 })
    }
}
