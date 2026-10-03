import DinkyCoreShared
import XCTest

final class CompressionOutcomeTests: XCTestCase {

    private func decide(_ original: Int64, _ output: Int64, min: Int = 2, forced: Bool = false, resized: Bool = false) -> CompressionOutcome {
        CompressionOutcomeDecider.decide(
            originalBytes: original, outputBytes: output,
            minimumSavingsPercent: min, forced: forced, didResize: resized
        )
    }

    func testSmallerIsKept() {
        XCTAssertEqual(decide(1000, 500), .keep)
    }

    func testEqualOrBiggerIsZeroGain() {
        XCTAssertEqual(decide(1000, 1000), .zeroGain)
        XCTAssertEqual(decide(1000, 1500), .zeroGain)
    }

    func testForceDoesNotKeepABiggerFile() {
        XCTAssertEqual(decide(1000, 1500, forced: true), .zeroGain)
    }

    func testUnderMinimumSavingsIsSkipped() {
        XCTAssertEqual(decide(1000, 990, min: 2), .skipped(savedPercent: 1))
    }

    func testForcedIgnoresMinimumSavings() {
        XCTAssertEqual(decide(1000, 990, min: 2, forced: true), .keep)
    }

    func testZeroMinimumKeepsAnySaving() {
        XCTAssertEqual(decide(1000, 999, min: 0), .keep)
    }

    /// A 3500 px image limited to 1200 px wide must come out 1200 px wide, even if the bytes didn't
    /// shrink (e.g. a heavily compressed JPEG re-encoded as PNG).
    func testResizedIsKeptEvenWhenBigger() {
        XCTAssertEqual(decide(1000, 1500, resized: true), .keep)
    }

    func testResizedIgnoresMinimumSavings() {
        XCTAssertEqual(decide(1000, 995, min: 10, resized: true), .keep)
    }

    func testEmptyOriginal() {
        XCTAssertEqual(decide(0, 0), .zeroGain)
    }
}
