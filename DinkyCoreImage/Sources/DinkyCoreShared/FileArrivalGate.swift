import Foundation

/// What a file in a watched folder looks like right now, for deciding whether it's finished arriving.
public struct FileArrivalSnapshot: Equatable, Sendable {
    public var exists: Bool
    public var size: Int64
    public var modificationDate: Date?
    /// Still being written by something that says so: Finder marks an in-progress copy with a
    /// pre-1970 creation date, and an iCloud file may not be downloaded yet.
    public var isBusy: Bool

    public init(exists: Bool, size: Int64, modificationDate: Date?, isBusy: Bool) {
        self.exists = exists
        self.size = size
        self.modificationDate = modificationDate
        self.isBusy = isBusy
    }

    public static let gone = FileArrivalSnapshot(exists: false, size: 0, modificationDate: nil, isBusy: false)

    public static func read(_ url: URL) -> FileArrivalSnapshot {
        let keys: Set<URLResourceKey> = [
            .fileSizeKey, .contentModificationDateKey, .creationDateKey,
            .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey,
        ]
        // Polled repeatedly: drop cached values so each read sees the file as it is now.
        var fresh = url
        fresh.removeAllCachedResourceValues()
        guard let v = try? fresh.resourceValues(forKeys: keys) else { return .gone }
        var busy = false
        if let created = v.creationDate, created < finderBusyCutoff { busy = true }
        if v.isUbiquitousItem == true, let status = v.ubiquitousItemDownloadingStatus, status != .current {
            busy = true
        }
        return FileArrivalSnapshot(
            exists: true,
            size: Int64(v.fileSize ?? 0),
            modificationDate: v.contentModificationDate,
            isBusy: busy
        )
    }

    /// Finder stamps copies in progress with 1904-01-01 or 1946-02-14; no real file predates 1970.
    static let finderBusyCutoff = Date(timeIntervalSince1970: 0)
}

/// Holds files that just showed up in a watched folder until they stop changing, so a large copy
/// isn't compressed half-written. Pure state machine — the caller supplies snapshots and the clock.
public struct FileArrivalGate: Sendable {
    public enum Verdict: Equatable, Sendable {
        case waiting
        /// Unchanged for the quiet period; safe to process.
        case ready
        /// Disappeared (moved away, deleted, or the copy was cancelled).
        case gone
        /// Never settled within `maxWait`.
        case gaveUp
    }

    private struct Entry: Sendable {
        let firstSeen: Date
        var last: FileArrivalSnapshot?
        var lastChange: Date
    }

    public var quietPeriod: TimeInterval
    /// A busy marker is trusted only while the file keeps changing; one left behind (e.g. by a
    /// copy that was interrupted and resumed) stops holding the file back after this long unchanged.
    public var busyGrace: TimeInterval
    public var maxWait: TimeInterval
    private var entries: [String: Entry] = [:]

    public init(quietPeriod: TimeInterval = 2, busyGrace: TimeInterval = 60, maxWait: TimeInterval = 30 * 60) {
        self.quietPeriod = quietPeriod
        self.busyGrace = busyGrace
        self.maxWait = maxWait
    }

    public var isEmpty: Bool { entries.isEmpty }
    public var pendingPaths: [String] { Array(entries.keys) }
    public func isTracking(_ path: String) -> Bool { entries[path] != nil }
    /// When the longest-waiting file was first seen.
    public var oldestFirstSeen: Date? { entries.values.map(\.firstSeen).min() }

    /// Starts waiting on `path`. Tracking a path again keeps its original first-seen time.
    public mutating func track(_ path: String, now: Date) {
        guard entries[path] == nil else { return }
        entries[path] = Entry(firstSeen: now, last: nil, lastChange: now)
    }

    public mutating func evaluate(_ path: String, snapshot: FileArrivalSnapshot, now: Date) -> Verdict {
        guard var entry = entries[path] else { return .gone }
        guard snapshot.exists else {
            entries[path] = nil
            return .gone
        }
        if now.timeIntervalSince(entry.firstSeen) > maxWait {
            entries[path] = nil
            return .gaveUp
        }
        if entry.last != snapshot {
            entry.last = snapshot
            entry.lastChange = now
            entries[path] = entry
            return .waiting
        }
        guard snapshot.size > 0 else { return .waiting }
        let settle = snapshot.isBusy ? busyGrace : quietPeriod
        guard now.timeIntervalSince(entry.lastChange) >= settle else { return .waiting }
        entries[path] = nil
        return .ready
    }

    public mutating func forget(_ path: String) {
        entries[path] = nil
    }
}
