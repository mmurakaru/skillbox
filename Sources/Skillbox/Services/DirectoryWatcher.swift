import Foundation
import CoreServices

/// FSEvents watches descendants and atomic file replacements without polling or one descriptor per file.
final class DirectoryWatcher {
    private var stream: FSEventStreamRef?
    private var debounceWorkItem: DispatchWorkItem?
    private let debounceLock = NSLock()
    private let watchedPaths: [String]
    private let onChange: () -> Void
    private let acceptsPath: (String) -> Bool
    private let eventQueue: DispatchQueue
    /// Serial queue for stream callbacks, so `deinit` can wait for an in-flight callback before freeing the watcher.
    private let streamQueue: DispatchQueue
    private let streamQueueKey = DispatchSpecificKey<Void>()
    /// Directories the FSEvents stream is rooted at, after resolving symlinks and missing paths.
    let streamRootPaths: Set<String>

    convenience init?(url: URL, acceptsPath: @escaping (String) -> Bool = { _ in true }, onChange: @escaping () -> Void) {
        self.init(urls: [url], acceptsPath: acceptsPath, onChange: onChange)
    }

    /// Turn off `watchesMissingPathsThroughAncestors` for large trees: a missing path's nearest ancestor can be the home folder.
    init?(
        urls: [URL],
        watchesMissingPathsThroughAncestors: Bool = true,
        // Releasing the watcher while running on `eventQueue` deadlocks, because `deinit` waits for that queue.
        eventQueue: DispatchQueue = .main,
        acceptsPath: @escaping (String) -> Bool = { _ in true },
        onChange: @escaping () -> Void
    ) {
        watchedPaths = urls.map { $0.resolvingSymlinksInPath().standardizedFileURL.path }
        self.onChange = onChange
        self.acceptsPath = acceptsPath
        self.eventQueue = eventQueue
        streamQueue = DispatchQueue(label: "DirectoryWatcher.stream", target: eventQueue)
        streamQueue.setSpecific(key: streamQueueKey, value: ())
        streamRootPaths = Set(watchedPaths.compactMap { path in
            var root = URL(fileURLWithPath: path)
            var directory: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &directory), !directory.boolValue {
                root.deleteLastPathComponent()
            }
            guard watchesMissingPathsThroughAncestors else {
                return FileManager.default.fileExists(atPath: root.path) ? root.path : nil
            }
            while !FileManager.default.fileExists(atPath: root.path), root.path != "/" {
                root.deleteLastPathComponent()
            }
            return root.path
        })
        guard !streamRootPaths.isEmpty else { return nil }
        let roots = streamRootPaths
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot)
        stream = FSEventStreamCreate(nil, { _, info, count, paths, eventFlags, _ in
            guard let info else { return }
            let watcher = Unmanaged<DirectoryWatcher>.fromOpaque(info).takeUnretainedValue()
            let changedPaths = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as! [String]
            let needsFullScan = (0..<count).contains {
                eventFlags[$0] & FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagRootChanged) != 0
            }
            if needsFullScan || changedPaths.contains(where: watcher.isRelevantPath) {
                watcher.scheduleChange()
            }
        }, &context, Array(roots) as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.2, flags)
        guard let stream else { return nil }
        FSEventStreamSetDispatchQueue(stream, streamQueue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
            return nil
        }
    }

    private func isRelevantPath(_ eventPath: String) -> Bool {
        let path = URL(fileURLWithPath: eventPath).resolvingSymlinksInPath().standardizedFileURL.path
        return acceptsPath(path) && watchedPaths.contains { watched in
            path == watched || path.hasPrefix(watched + "/") || watched.hasPrefix(path + "/")
        }
    }

    /// Runs on the event queue; the debounce lives there too so only the final callback hops to the main thread.
    private func scheduleChange() {
        let onChange = self.onChange
        let work = DispatchWorkItem { DispatchQueue.main.async(execute: onChange) }
        debounceLock.withLock {
            debounceWorkItem?.cancel()
            debounceWorkItem = work
        }
        streamQueue.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    deinit {
        debounceLock.withLock { debounceWorkItem?.cancel() }
        guard let stream else { return }
        let stopStream = {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        let isOnStreamQueue = DispatchQueue.getSpecific(key: streamQueueKey) != nil || (eventQueue === DispatchQueue.main && Thread.isMainThread)
        if isOnStreamQueue {
            stopStream()
        } else {
            streamQueue.sync(execute: stopStream)
        }
    }
}
