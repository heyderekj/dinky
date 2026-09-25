import DinkyCoreShared
import XCTest

/// A large file copied into a watch folder must not be compressed until it stops changing.
final class FileArrivalGateTests: XCTestCase {

    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }
    private func snap(_ size: Int64, mtime: TimeInterval = 0, busy: Bool = false) -> FileArrivalSnapshot {
        FileArrivalSnapshot(exists: true, size: size, modificationDate: at(mtime), isBusy: busy)
    }

    func testReadyAfterQuietPeriod() {
        var g = FileArrivalGate(quietPeriod: 2)
        g.track("a", now: at(0))
        XCTAssertEqual(g.evaluate("a", snapshot: snap(100), now: at(0)), .waiting)
        XCTAssertEqual(g.evaluate("a", snapshot: snap(100), now: at(1)), .waiting)
        XCTAssertEqual(g.evaluate("a", snapshot: snap(100), now: at(2)), .ready)
        XCTAssertTrue(g.isEmpty)
    }

    func testGrowingFileResetsTheClock() {
        var g = FileArrivalGate(quietPeriod: 2)
        g.track("a", now: at(0))
        _ = g.evaluate("a", snapshot: snap(100), now: at(0))
        XCTAssertEqual(g.evaluate("a", snapshot: snap(5_000), now: at(1.5)), .waiting)
        XCTAssertEqual(g.evaluate("a", snapshot: snap(5_000), now: at(3)), .waiting)
        XCTAssertEqual(g.evaluate("a", snapshot: snap(5_000), now: at(3.5)), .ready)
    }

    func testModificationDateChangeResetsTheClock() {
        var g = FileArrivalGate(quietPeriod: 2)
        g.track("a", now: at(0))
        _ = g.evaluate("a", snapshot: snap(100, mtime: 0), now: at(0))
        XCTAssertEqual(g.evaluate("a", snapshot: snap(100, mtime: 1), now: at(1)), .waiting)
        XCTAssertEqual(g.evaluate("a", snapshot: snap(100, mtime: 1), now: at(2.5)), .waiting)
        XCTAssertEqual(g.evaluate("a", snapshot: snap(100, mtime: 1), now: at(3)), .ready)
    }

    /// Finder can pre-allocate the full size, so a copy in progress can look stable — its busy
    /// marker is what holds it back.
    func testBusyFileWaits() {
        var g = FileArrivalGate(quietPeriod: 2, busyGrace: 60)
        g.track("a", now: at(0))
        _ = g.evaluate("a", snapshot: snap(100, busy: true), now: at(0))
        XCTAssertEqual(g.evaluate("a", snapshot: snap(100, busy: true), now: at(10)), .waiting)
        XCTAssertEqual(g.evaluate("a", snapshot: snap(100), now: at(11)), .waiting)
        XCTAssertEqual(g.evaluate("a", snapshot: snap(100), now: at(13)), .ready)
    }

    /// A busy marker left behind on a file that stopped changing must not block it forever.
    func testStaleBusyMarkerEventuallyReleases() {
        var g = FileArrivalGate(quietPeriod: 2, busyGrace: 60)
        g.track("a", now: at(0))
        _ = g.evaluate("a", snapshot: snap(100, busy: true), now: at(0))
        XCTAssertEqual(g.evaluate("a", snapshot: snap(100, busy: true), now: at(59)), .waiting)
        XCTAssertEqual(g.evaluate("a", snapshot: snap(100, busy: true), now: at(60)), .ready)
    }

    func testEmptyFileWaits() {
        var g = FileArrivalGate(quietPeriod: 2)
        g.track("a", now: at(0))
        _ = g.evaluate("a", snapshot: snap(0), now: at(0))
        XCTAssertEqual(g.evaluate("a", snapshot: snap(0), now: at(10)), .waiting)
    }

    func testFileThatDisappearsIsDropped() {
        var g = FileArrivalGate()
        g.track("a", now: at(0))
        XCTAssertEqual(g.evaluate("a", snapshot: .gone, now: at(1)), .gone)
        XCTAssertFalse(g.isTracking("a"))
    }

    func testGivesUpAfterMaxWait() {
        var g = FileArrivalGate(quietPeriod: 2, maxWait: 60)
        g.track("a", now: at(0))
        _ = g.evaluate("a", snapshot: snap(0), now: at(0))
        XCTAssertEqual(g.evaluate("a", snapshot: snap(0), now: at(61)), .gaveUp)
        XCTAssertTrue(g.isEmpty)
    }

    func testRetrackingKeepsFirstSeen() {
        var g = FileArrivalGate(quietPeriod: 2, maxWait: 60)
        g.track("a", now: at(0))
        g.track("a", now: at(50))
        XCTAssertEqual(g.oldestFirstSeen, at(0))
    }

    func testFinderBusyDateIsBusy() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dinky-busy-\(UUID().uuidString).jpg")
        try Data([1, 2, 3]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertFalse(FileArrivalSnapshot.read(url).isBusy)
        // Finder's copy-in-progress creation date.
        try FileManager.default.setAttributes([.creationDate: Date(timeIntervalSince1970: -2_082_844_800)], ofItemAtPath: url.path)
        XCTAssertTrue(FileArrivalSnapshot.read(url).isBusy)
        XCTAssertEqual(FileArrivalSnapshot.read(url).size, 3)
    }
}
