import Foundation

final class FolderWatcher: ObservableObject {
    var onNewFiles: (([URL]) -> Void)?
    private var stream: FSEventStreamRef?
    private var retainedSelf: UnsafeMutableRawPointer?
    private let imageExtensions = Set(["jpg", "jpeg", "png", "webp", "avif", "tiff", "bmp"])

    func start(at path: String) {
        stop()
        let retained = Unmanaged.passRetained(self).toOpaque()
        retainedSelf = retained
        var ctx = FSEventStreamContext(version: 0, info: retained,
                                       retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, eventPaths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
            guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }
            let now = Date()
            let imageExts = watcher.imageExtensions
            let urls = paths
                .map { URL(fileURLWithPath: $0) }
                .filter { imageExts.contains($0.pathExtension.lowercased()) }
                .filter { url in
                    guard let created = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate else { return false }
                    return now.timeIntervalSince(created) < 10
                }
            guard !urls.isEmpty else { return }
            // Dispatch async so the FSEvents callback can return before @MainActor work runs.
            // Calling a @MainActor-isolated method synchronously from a DispatchSource callback
            // on DispatchQueue.main deadlocks the Swift concurrency executor.
            DispatchQueue.main.async { watcher.onNewFiles?(urls) }
        }

        stream = FSEventStreamCreate(
            nil, callback, &ctx,
            [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.5,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        )
        guard let stream else {
            Unmanaged<FolderWatcher>.fromOpaque(retained).release()
            retainedSelf = nil
            return
        }
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
    }

    func stop() {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
        if let retained = retainedSelf {
            Unmanaged<FolderWatcher>.fromOpaque(retained).release()
            retainedSelf = nil
        }
    }

    deinit { stop() }
}
