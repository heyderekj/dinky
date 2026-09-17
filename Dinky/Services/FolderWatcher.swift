import Foundation


final class FolderWatcher: ObservableObject {
    var onNewFiles: (([URL]) -> Void)?
    private var stream: FSEventStreamRef?
    private var retainedSelf: UnsafeMutableRawPointer?

    /// Subscribes to filesystem changes under one or more directories (`paths` must be non-empty).
    func start(paths: [String]) {
        stop()
        let normalized = paths
            .map { ($0 as NSString).standardizingPath }
            .filter { !$0.isEmpty }
        guard !normalized.isEmpty else { return }

        let retained = Unmanaged.passRetained(self).toOpaque()
        retainedSelf = retained
        var ctx = FSEventStreamContext(version: 0, info: retained,
                                       retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, eventPaths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
            let cfPaths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue()
            guard let paths = cfPaths as? [String] else { return }
            let now = Date()
            let urls = paths
                .map { URL(fileURLWithPath: $0) }
                .filter { MediaTypeDetector.detect($0) != nil }
                .filter { url in
                    guard let rv = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey]),
                          let created = rv.creationDate else { return false }
                    let modified = rv.contentModificationDate ?? created
                    let ref = modified > created ? modified : created
                    return now.timeIntervalSince(ref) < 30
                }
            guard !urls.isEmpty else { return }
            DispatchQueue.main.async { watcher.onNewFiles?(urls) }
        }

        stream = FSEventStreamCreate(
            nil, callback, &ctx,
            normalized as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.5,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagUseCFTypes)
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
