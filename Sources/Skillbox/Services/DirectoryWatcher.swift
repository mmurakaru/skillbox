import Foundation

final class DirectoryWatcher {
    private let fd: Int32
    private let source: DispatchSourceFileSystemObject
    private let queue = DispatchQueue(label: "com.skillbox.watcher")
    private var debounceWorkItem: DispatchWorkItem?
    private let debounceInterval: TimeInterval = 0.2

    init?(url: URL, onChange: @escaping () -> Void) {
        fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return nil }

        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .extend, .attrib],
            queue: queue
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            self.debounceWorkItem?.cancel()
            let work = DispatchWorkItem { onChange() }
            self.debounceWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + self.debounceInterval, execute: work)
        }

        let capturedFd = fd
        source.setCancelHandler { close(capturedFd) }
        source.resume()
    }

    deinit {
        debounceWorkItem?.cancel()
        source.cancel()
    }
}
