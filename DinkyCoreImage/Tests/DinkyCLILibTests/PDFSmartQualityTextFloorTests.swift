import AppKit
import CoreText
import DinkyCorePDF
import Foundation
import XCTest

/// Smart quality used to pick Smallest (72 DPI) for plain text pages, which flattens to mush.
final class PDFSmartQualityTextFloorTests: XCTestCase {
    func testTextDocumentNeverGoesBelowMedium() throws {
        let url = try writeTextPDF(pages: 3)
        defer { try? FileManager.default.removeItem(at: url) }
        for fallback in PDFQuality.allCases {
            let q = PDFSmartQuality.inferQuality(url: url, fallback: fallback)
            XCTAssertTrue(q == .medium || q == .high, "picked \(q.rawValue) for a text document")
            let (flat, _) = PDFSmartQuality.inferFlattenQualityAndMono(url: url, fallback: fallback, autoGrayscaleMonoScans: true)
            XCTAssertTrue(flat == .medium || flat == .high, "picked \(flat.rawValue) for a text document")
        }
    }

    private func writeTextPDF(pages: Int) throws -> URL {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let consumer = try XCTUnwrap(CGDataConsumer(data: data as CFMutableData))
        let ctx = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &box, nil))
        let paragraph = String(repeating: "On April 14, customers saw errors when opening hosted sites and the dashboard. ", count: 40)
        let text = NSAttributedString(string: paragraph, attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.black,
        ])
        for _ in 0..<pages {
            ctx.beginPDFPage(nil)
            let framesetter = CTFramesetterCreateWithAttributedString(text)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: text.length),
                                                 CGPath(rect: box.insetBy(dx: 72, dy: 72), transform: nil), nil)
            CTFrameDraw(frame, ctx)
            ctx.endPDFPage()
        }
        ctx.closePDF()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dinky-text-\(UUID().uuidString).pdf")
        try (data as Data).write(to: url)
        return url
    }
}
