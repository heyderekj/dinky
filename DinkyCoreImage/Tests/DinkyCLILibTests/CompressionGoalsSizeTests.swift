import DinkyCoreImage
import XCTest

/// Pure size math for percentage scaling and the max width cap (no encoders needed).
final class CompressionGoalsSizeTests: XCTestCase {
    func testNoGoalsLeavesSizeAlone() {
        XCTAssertNil(CompressionGoals().outputPixelSize(width: 800, height: 600))
    }

    func testScaleKeepsProportions() throws {
        let size = try XCTUnwrap(CompressionGoals(scalePercent: 50).outputPixelSize(width: 800, height: 600))
        XCTAssertEqual(size.width, 400)
        XCTAssertEqual(size.height, 300)
    }

    func testPortraitScale() throws {
        let size = try XCTUnwrap(CompressionGoals(scalePercent: 50).outputPixelSize(width: 600, height: 800))
        XCTAssertEqual(size.width, 300)
        XCTAssertEqual(size.height, 400)
    }

    func testTinyScaleNeverReachesZero() throws {
        let size = try XCTUnwrap(CompressionGoals(scalePercent: 1).outputPixelSize(width: 20, height: 10))
        XCTAssertEqual(size.width, 1)
        XCTAssertEqual(size.height, 1)
    }

    func testMaxWidthAppliesAfterScale() throws {
        let goals = CompressionGoals(maxWidth: 500, scalePercent: 50)
        let size = try XCTUnwrap(goals.outputPixelSize(width: 2000, height: 1000))
        XCTAssertEqual(size.width, 500)
        XCTAssertEqual(size.height, 250)
    }

    func testScaleUnderMaxWidthIsKept() throws {
        let goals = CompressionGoals(maxWidth: 1920, scalePercent: 25)
        let size = try XCTUnwrap(goals.outputPixelSize(width: 4000, height: 3000))
        XCTAssertEqual(size.width, 1000)
        XCTAssertEqual(size.height, 750)
    }

    func testPercentagesAreClampedToShrinkOnly() {
        XCTAssertEqual(CompressionGoals(scalePercent: 0).scalePercent, 1)
        XCTAssertEqual(CompressionGoals(scalePercent: 150).scalePercent, 100)
        XCTAssertNil(CompressionGoals(scalePercent: 150).outputPixelSize(width: 100, height: 60))
    }

    func testIdentityScaleDoesNotChangeDimensions() {
        XCTAssertFalse(CompressionGoals(scalePercent: 100).changesDimensions)
        XCTAssertTrue(CompressionGoals(scalePercent: 99).changesDimensions)
    }
}
