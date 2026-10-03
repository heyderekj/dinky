import DinkyCoreShared
import XCTest

final class BatchScopeTests: XCTestCase {

    private struct Row { let id: UUID; let saved: Int64 }

    func testOnlyThisBatchsRowsCount() {
        let earlier = Row(id: UUID(), saved: 500)
        let a = Row(id: UUID(), saved: 100)
        let b = Row(id: UUID(), saved: 50)
        let scoped = BatchScope.items([earlier, a, b], in: [a.id, b.id], id: \.id)
        XCTAssertEqual(scoped.map(\.id), [a.id, b.id])
        XCTAssertEqual(scoped.reduce(0) { $0 + $1.saved }, 150)
    }

    func testRowsRemovedSinceTheBatchAreSimplyMissing() {
        let a = Row(id: UUID(), saved: 100)
        let scoped = BatchScope.items([a], in: [a.id, UUID()], id: \.id)
        XCTAssertEqual(scoped.map(\.id), [a.id])
    }

    func testLegacySummaryWithoutIdsUsesEveryRow() {
        let rows = [Row(id: UUID(), saved: 1), Row(id: UUID(), saved: 2)]
        XCTAssertEqual(BatchScope.items(rows, in: nil, id: \.id).count, 2)
    }
}
