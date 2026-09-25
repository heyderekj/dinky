import Foundation

/// Watch-folder files Dinky has already taken in, so a repeat filesystem event — or the same file
/// seen again after its row was cleared — doesn't compress it twice. A changed file is new again.
public struct WatchIngestLedger: Sendable {
    private var seen: [String: (fingerprint: FileFingerprint?, at: Date)] = [:]
    public var ttl: TimeInterval
    public var capacity: Int

    public init(ttl: TimeInterval = 24 * 60 * 60, capacity: Int = 500) {
        self.ttl = ttl
        self.capacity = capacity
    }

    public func alreadyIngested(_ path: String, fingerprint: FileFingerprint?, now: Date) -> Bool {
        guard let entry = seen[path], now.timeIntervalSince(entry.at) < ttl else { return false }
        return entry.fingerprint == fingerprint
    }

    public mutating func record(_ path: String, fingerprint: FileFingerprint?, now: Date) {
        seen[path] = (fingerprint, now)
        seen = seen.filter { now.timeIntervalSince($0.value.at) < ttl }
        if seen.count > capacity {
            let keep = seen.sorted { $0.value.at > $1.value.at }.prefix(capacity)
            seen = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
    }

    public mutating func forget(_ path: String) {
        seen[path] = nil
    }
}

/// Path containment for watch roots, shared with the app's registry.
public enum WatchPaths {
    public static func normalized(_ path: String) -> String {
        (path as NSString).standardizingPath
    }

    /// Whether `path` is `root` or inside it.
    public static func path(_ path: String, isUnder root: String) -> Bool {
        let r = normalized(root)
        let p = normalized(path)
        guard !r.isEmpty else { return false }
        return p == r || p.hasPrefix(r.hasSuffix("/") ? r : r + "/")
    }
}
