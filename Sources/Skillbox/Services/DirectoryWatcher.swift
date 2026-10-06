import Foundation
import CoreServices

/// FSEvents watches descendants and atomic file replacements without polling or one descriptor per file.
final class DirectoryWatcher {
    private var stream: FSEventStreamRef?
    private var debounceWorkItem: DispatchWorkItem?
    private let watchedPaths: [String]
    private let onChange: () -> Void
    private let acceptsPath: (String) -> Bool

    convenience init?(url: URL, acceptsPath: @escaping (String) -> Bool = { _ in true }, onChange: @escaping () -> Void) {
        self.init(urls: [url], acceptsPath: acceptsPath, onChange: onChange)
    }

    init?(urls: [URL], acceptsPath: @escaping (String) -> Bool = { _ in true }, onChange: @escaping () -> Void) {
        watchedPaths = urls.map { $0.resolvingSymlinksInPath().standardizedFileURL.path }
        self.onChange = onChange
        self.acceptsPath = acceptsPath
        let roots = Set(watchedPaths.map { path in
            var root = URL(fileURLWithPath: path)
            var directory: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &directory), !directory.boolValue {
                root.deleteLastPathComponent()
            }
            // Watch an existing ancestor so missing roots and files can appear later.
            while !FileManager.default.fileExists(atPath: root.path), root.path != "/" {
                root.deleteLastPathComponent()
            }
            return root.path
        })
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
        FSEventStreamSetDispatchQueue(stream, .main)
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

    private func scheduleChange() {
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange() }
        debounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    deinit {
        debounceWorkItem?.cancel()
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }
}
