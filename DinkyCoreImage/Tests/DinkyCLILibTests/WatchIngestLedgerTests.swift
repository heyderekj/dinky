import DinkyCoreShared
import XCTest

final class WatchIngestLedgerTests: XCTestCase {

    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let fp = FileFingerprint(size: 10, modificationDate: Date(timeIntervalSinceReferenceDate: 1))

    func testSameFileIsNotIngestedTwice() {
        var l = WatchIngestLedger()
        l.record("/w/a.jpg", fingerprint: fp, now: now)
        XCTAssertTrue(l.alreadyIngested("/w/a.jpg", fingerprint: fp, now: now.addingTimeInterval(60)))
    }

    func testChangedFileIsNew() {
        var l = WatchIngestLedger()
        l.record("/w/a.jpg", fingerprint: fp, now: now)
        let changed = FileFingerprint(size: 11, modificationDate: fp.modificationDate)
        XCTAssertFalse(l.alreadyIngested("/w/a.jpg", fingerprint: changed, now: now))
    }

    func testEntriesExpire() {
        var l = WatchIngestLedger(ttl: 100)
        l.record("/w/a.jpg", fingerprint: fp, now: now)
        XCTAssertFalse(l.alreadyIngested("/w/a.jpg", fingerprint: fp, now: now.addingTimeInterval(101)))
    }

    func testCapacityKeepsNewest() {
        var l = WatchIngestLedger(capacity: 2)
        l.record("/1", fingerprint: fp, now: now)
        l.record("/2", fingerprint: fp, now: now.addingTimeInterval(1))
        l.record("/3", fingerprint: fp, now: now.addingTimeInterval(2))
        XCTAssertFalse(l.alreadyIngested("/1", fingerprint: fp, now: now.addingTimeInterval(3)))
        XCTAssertTrue(l.alreadyIngested("/3", fingerprint: fp, now: now.addingTimeInterval(3)))
    }

    func testPathContainment() {
        XCTAssertTrue(WatchPaths.path("/Users/me/Inbox/Backup/a.jpg", isUnder: "/Users/me/Inbox"))
        XCTAssertTrue(WatchPaths.path("/Users/me/Inbox", isUnder: "/Users/me/Inbox/"))
        XCTAssertFalse(WatchPaths.path("/Users/me/Inbox2/a.jpg", isUnder: "/Users/me/Inbox"))
        XCTAssertFalse(WatchPaths.path("/a.jpg", isUnder: ""))
    }
}

final class FileFingerprintTests: XCTestCase {
    func testSameFileMatchesAndRecopyDoesNot() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("dinky-fp-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let src = dir.appendingPathComponent("src.jpg")
        try Data(repeating: 7, count: 100).write(to: src)
        let watched = dir.appendingPathComponent("in.jpg")
        try FileManager.default.copyItem(at: src, to: watched)
        let first = try XCTUnwrap(FileFingerprint(url: watched))
        XCTAssertEqual(FileFingerprint(url: watched), first, "repeat reads of one arrival match")
        XCTAssertEqual(first.size, 100)
    }
}
