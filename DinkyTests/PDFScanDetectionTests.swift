import XCTest
import DinkyCoreShared

final class PDFScanDetectionTests: XCTestCase {

    func testScanLikelihoodLowWhenDenseText() {
        let s = PDFDocumentSignals(
            pageCount: 5,
            bytesPerPage: 80_000,
            avgChromaSpread: 0.06,
            avgNonWhiteFill: 0.15,
            totalTextCharsSampled: 1200
        )
        XCTAssertLessThan(s.scanLikelihood, PDFScanDetection.ocrLikelihoodThreshold)
    }

    func testScanLikelihoodHigherWhenImageHeavyLowText() {
        let s = PDFDocumentSignals(
            pageCount: 3,
            bytesPerPage: 220_000,
            avgChromaSpread: 0.04,
            avgNonWhiteFill: 0.18,
            totalTextCharsSampled: 8
        )
        XCTAssertGreaterThan(s.scanLikelihood, 0.15)
    }

    func testOcrThreshold() {
        XCTAssertEqual(PDFScanDetection.ocrLikelihoodThreshold, 0.42, accuracy: 0.0001)
    }
}
