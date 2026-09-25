import Foundation
import os

/// Activity log for watch folders — `log stream --level info --predicate 'subsystem == "com.dinky.app" AND category == "watch"'`.
let watchLog = Logger(subsystem: "com.dinky.app", category: "watch")

final class FolderWatcher: ObservableObject {
    /// Files that finished arriving (stopped changing) and are ready to compress.
    var onReadyFiles: (([URL]) -> Void)?
    /// Paths not worth waiting on at all — Dinky's own output being written into the folder.
    var shouldIgnore: ((URL) -> Bool)?
    private var stream: FSEventStreamRef?
    private var retainedSelf: UnsafeMutableRawPointer?

    /// Files seen but possibly still being written. Polled until they settle, so a large copy
    /// isn't compressed half-written — and isn't missed because its last event came too late.
    private var gate = FileArrivalGate()
    private var pollTimer: Timer?

    /// How far back an event's file may have arrived and still count as new. Generous so a slow
    /// copy's final events aren't dropped; the ingest ledger stops repeats.
    static let recentArrivalWindow: TimeInterval = 10 * 60

    /// When a file effectively landed in its folder. Moving or Finder-copying a file in keeps its
    /// original creation and modification dates, so a download dragged in just now can look days
    /// old; the date it was added to the directory is the one that actually changes.
    static func arrivalDate(of url: URL) -> Date? {
        guard let values = try? url.resourceValues(
            forKeys: [.creationDateKey, .contentModificationDateKey, .addedToDirectoryDateKey]
        ) else { return nil }
        return [values.creationDate, values.contentModificationDate, values.addedToDirectoryDate]
            .compactMap { $0 }
            .max()
    }

    /// When the longest-waiting file was first seen, so a relaunch's catch-up scan doesn't skip a
    /// file that was still copying at quit.
    var oldestPendingSince: Date? { gate.oldestFirstSeen }

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
            let urls = paths.map { URL(fileURLWithPath: $0) }
            DispatchQueue.main.async { watcher.handleEvents(urls) }
        }

        stream = FSEventStreamCreate(
            nil, callback, &ctx,
            normalized as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagUseCFTypes)
        )
        guard let stream else {
            Unmanaged<FolderWatcher>.fromOpaque(retained).release()
            retainedSelf = nil
            watchLog.error("FSEvents stream could not be created for \(normalized.count, privacy: .public) folder(s)")
            return
        }
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
        watchLog.notice("Watching \(normalized.count, privacy: .public) folder(s)")
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

    private func handleEvents(_ urls: [URL]) {
        let now = Date()
        var fresh: [URL] = []
        for url in urls {
            guard !url.lastPathComponent.hasPrefix("."), MediaTypeDetector.detect(url) != nil else { continue }
            if gate.isTracking(url.path) || shouldIgnore?(url) == true { continue }
            let snapshot = FileArrivalSnapshot.read(url)
            guard snapshot.exists else { continue }
            // Old files touched in place (metadata edits, Spotlight) aren't new arrivals; a copy
            // still in progress is, however old its preserved dates look.
            let recent = FolderWatcher.arrivalDate(of: url).map { now.timeIntervalSince($0) < Self.recentArrivalWindow } ?? false
            guard recent || snapshot.isBusy else {
                watchLog.debug("Ignored old file \(url.lastPathComponent, privacy: .private(mask: .hash))")
                continue
            }
            fresh.append(url)
        }
        enqueue(fresh)
    }

    /// Waits for each file to finish arriving, then hands it to `onReadyFiles`.
    func enqueue(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let now = Date()
        for url in urls where !gate.isTracking(url.path) {
            gate.track(url.path, now: now)
            watchLog.info("Waiting for \(url.lastPathComponent, privacy: .private(mask: .hash)) to finish arriving")
        }
        poll()
        if !gate.isEmpty, pollTimer == nil {
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.poll() }
            RunLoop.main.add(timer, forMode: .common)
            pollTimer = timer
        }
    }

    private func poll() {
        let now = Date()
        var ready: [URL] = []
        for path in gate.pendingPaths {
            let url = URL(fileURLWithPath: path)
            switch gate.evaluate(path, snapshot: FileArrivalSnapshot.read(url), now: now) {
            case .waiting:
                break
            case .ready:
                ready.append(url)
            case .gone:
                watchLog.info("\(url.lastPathComponent, privacy: .private(mask: .hash)) left the folder before it settled")
            case .gaveUp:
                watchLog.notice("Gave up waiting for \(url.lastPathComponent, privacy: .private(mask: .hash)) to finish arriving")
            }
        }
        if gate.isEmpty {
            pollTimer?.invalidate()
            pollTimer = nil
        }
        if !ready.isEmpty {
            watchLog.info("\(ready.count, privacy: .public) file(s) ready")
            onReadyFiles?(ready)
        }
    }

    deinit {
        pollTimer?.invalidate()
        stop()
    }
}
