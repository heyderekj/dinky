import CoreGraphics
import DinkyCorePDF
import Foundation
import PDFKit
import XCTest

/// Rasterized PDF pages must keep the size and orientation viewers show: crop box, rotation applied.
final class PDFPageGeometryTests: XCTestCase {
    private struct Fixture {
        let name: String
        let mediaBox: CGRect
        var cropBox: CGRect?
        var rotation = 0
        /// The visible page's size once rotation is applied.
        let displaySize: CGSize
        /// Unrotated page-space rect painted red; it should end up in the output's top-right.
        let mark: CGRect
    }

    private let fixtures: [Fixture] = [
        Fixture(name: "bleed", mediaBox: CGRect(x: 0, y: 0, width: 684, height: 864),
                cropBox: CGRect(x: 36, y: 36, width: 612, height: 792),
                displaySize: CGSize(width: 612, height: 792),
                mark: CGRect(x: 36 + 612 - 80, y: 36 + 792 - 80, width: 80, height: 80)),
        // Turned a quarter clockwise, the page's top-left corner lands in the top-right.
        Fixture(name: "rotated", mediaBox: CGRect(x: 0, y: 0, width: 612, height: 792), rotation: 90,
                displaySize: CGSize(width: 792, height: 612),
                mark: CGRect(x: 0, y: 792 - 80, width: 80, height: 80)),
        Fixture(name: "offset", mediaBox: CGRect(x: 100, y: 200, width: 500, height: 400),
                displaySize: CGSize(width: 500, height: 400),
                mark: CGRect(x: 600 - 80, y: 600 - 80, width: 80, height: 80)),
    ]

    func testFlattenKeepsVisiblePageGeometry() async throws {
        for f in fixtures {
            let src = try makePDF(f)
            let out = FileManager.default.temporaryDirectory.appendingPathComponent("dinky-geo-out-\(UUID().uuidString).pdf")
            defer { try? FileManager.default.removeItem(at: src); try? FileManager.default.removeItem(at: out) }
            let result = try await DinkyPDFPipeline.compress(
                source: src, outputMode: .flattenPages, quality: .medium, grayscale: false,
                stripMetadata: true, outputURL: out, qpdfBinary: nil
            )
            defer { try? FileManager.default.removeItem(at: result.outputURL) }
            let doc = try XCTUnwrap(PDFDocument(url: result.outputURL), f.name)
            try assertGeometry(of: XCTUnwrap(doc.page(at: 0)), matches: f)
        }
    }

    func testDownsampleKeepsVisiblePageGeometry() throws {
        for f in fixtures {
            let src = try makePDF(f)
            defer { try? FileManager.default.removeItem(at: src) }
            let structure = try XCTUnwrap(PDFDocument(url: src))
            let mixed = try XCTUnwrap(PDFImageDownsampler.downsample(source: src, structureDoc: structure, stripMetadata: true), f.name)
            // Round-trip through a file, as the pipeline does.
            let out = FileManager.default.temporaryDirectory.appendingPathComponent("dinky-geo-ds-\(UUID().uuidString).pdf")
            defer { try? FileManager.default.removeItem(at: out) }
            XCTAssertTrue(mixed.write(to: out))
            let doc = try XCTUnwrap(PDFDocument(url: out))
            try assertGeometry(of: XCTUnwrap(doc.page(at: 0)), matches: f)
        }
    }

    // MARK: - Helpers

    private func makePDF(_ f: Fixture) throws -> URL {
        let data = NSMutableData()
        var media = f.mediaBox
        let consumer = try XCTUnwrap(CGDataConsumer(data: data as CFMutableData))
        let ctx = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &media, nil))
        var info: [CFString: Any] = [kCGPDFContextMediaBox: NSData(bytes: &media, length: MemoryLayout<CGRect>.size)]
        if var crop = f.cropBox {
            info[kCGPDFContextCropBox] = NSData(bytes: &crop, length: MemoryLayout<CGRect>.size)
        }
        ctx.beginPDFPage(info as CFDictionary)
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        ctx.fill(f.mediaBox)
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(f.mark)
        ctx.endPDFPage()
        ctx.closePDF()

        let doc = try XCTUnwrap(PDFDocument(data: data as Data))
        if f.rotation != 0 { doc.page(at: 0)?.rotation = f.rotation }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dinky-geo-\(f.name)-\(UUID().uuidString).pdf")
        XCTAssertTrue(doc.write(to: url))
        return url
    }

    private func assertGeometry(of page: PDFPage, matches f: Fixture, file: StaticString = #filePath, line: UInt = #line) throws {
        let box = page.bounds(for: .cropBox)
        XCTAssertEqual(page.rotation, 0, f.name, file: file, line: line)
        XCTAssertEqual(box.width, f.displaySize.width, accuracy: 1, f.name, file: file, line: line)
        XCTAssertEqual(box.height, f.displaySize.height, accuracy: 1, f.name, file: file, line: line)

        // Render the output with plain Quartz, independent of the code under test.
        let w = Int(box.width), h = Int(box.height)
        let ctx = try XCTUnwrap(CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        let cgPage = try XCTUnwrap(page.pageRef)
        ctx.translateBy(x: -box.minX, y: -box.minY)
        ctx.drawPDFPage(cgPage)
        let px = try XCTUnwrap(ctx.data).bindMemory(to: UInt8.self, capacity: w * h * 4)
        // Bitmap rows run top-down.
        func isRed(x: Int, yFromTop: Int) -> Bool {
            let i = (yFromTop * w + x) * 4
            return px[i] > 180 && px[i + 2] < 90
        }
        XCTAssertTrue(isRed(x: w - 40, yFromTop: 40), "\(f.name): mark missing from top-right", file: file, line: line)
        XCTAssertFalse(isRed(x: 40, yFromTop: h - 40), "\(f.name): bottom-left should be blue", file: file, line: line)
        XCTAssertFalse(isRed(x: 40, yFromTop: 40), "\(f.name): top-left should be blue", file: file, line: line)
    }
}
