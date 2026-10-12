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

    @Test func noCallbackRunsAfterReleasingAWatcherWithQueuedEvents() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("skillbox-watchrelease-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let eventQueue = DispatchQueue(label: "watcher-release-test")
        let progress = WatcherCallbackProgress()
        let holder = WatcherHolder()
        holder.watcher = DirectoryWatcher(urls: [root], eventQueue: eventQueue) { _ in
            progress.recordCallback()
            return true
        } onChange: {}
        #expect(holder.watcher != nil)

        // Holding the queue makes FSEvents queue its callback behind this block, so release races a pending callback.
        eventQueue.async { Thread.sleep(forTimeInterval: 0.8) }
        try "change".write(to: root.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
        try await Task.sleep(for: .milliseconds(400))
        await Task.detached { releaseWatcher(holder: holder, progress: progress) }.value
        try await Task.sleep(for: .milliseconds(800))

        #expect(progress.callbacksAfterRelease == 0)
    }

    @Test func eventsQueuedBehindABusyEventQueueAreDeliveredOnceItFrees() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("skillbox-watchbusy-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let eventQueue = DispatchQueue(label: "watcher-busy-test")
        let progress = WatcherCallbackProgress()
        let watcher = DirectoryWatcher(urls: [root], eventQueue: eventQueue) { _ in
            progress.recordCallback()
            return true
        } onChange: {}
        defer { withExtendedLifetime(watcher) {} }

        eventQueue.async { Thread.sleep(forTimeInterval: 0.8) }
        try "change".write(to: root.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
        try await Task.sleep(for: .milliseconds(1600))

        #expect(progress.callbackCount > 0)
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

private func releaseWatcher(holder: WatcherHolder, progress: WatcherCallbackProgress) {
    holder.watcher = nil
    progress.markReleased()
}

/// Counts callbacks from the watcher's queue that arrive after the test released the watcher.
private final class WatcherCallbackProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var released = false
    private var lateCallbacks = 0
    private var totalCallbacks = 0

    var callbacksAfterRelease: Int { lock.withLock { lateCallbacks } }
    var callbackCount: Int { lock.withLock { totalCallbacks } }

    func markReleased() { lock.withLock { released = true } }
    func recordCallback() { lock.withLock { totalCallbacks += 1; if released { lateCallbacks += 1 } } }
}

/// Lets the test release the watcher from a background thread.
private final class WatcherHolder: @unchecked Sendable {
    var watcher: DirectoryWatcher?
}
