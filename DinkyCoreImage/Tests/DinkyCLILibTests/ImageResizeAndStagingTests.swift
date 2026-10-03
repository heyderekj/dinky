import CoreGraphics
import DinkyCoreImage
import DinkyCoreShared
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest

/// The encoder never writes over the source, and reports when a width limit resized the image —
/// the app needs both to decide what to keep before anything happens to the original.
final class ImageResizeAndStagingTests: XCTestCase {

    private var bin: URL!
    private var workDir: URL!

    override func setUpWithError() throws {
        guard let bin = DinkyEncoderPath.resolveBinDirectory() else {
            throw XCTSkip("Encoders not available in this environment.")
        }
        self.bin = bin
        workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dinky-resize-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let workDir { try? FileManager.default.removeItem(at: workDir) }
    }

    func testWidthLimitReportsResize() async throws {
        let src = try writePNG(named: "wide", width: 3000, height: 100)
        let out = workDir.appendingPathComponent("wide-out.webp")
        let r = try await compress(src, format: .webp, output: out, maxWidth: 1200)
        XCTAssertEqual(r.resize, ImageResizeInfo(originalWidth: 3000, originalHeight: 100, outputWidth: 1200, outputHeight: 40))
        let size = try pixelSize(r.outputURL)
        XCTAssertEqual(size.width, 1200)
    }

    func testNarrowImageIsNotResized() async throws {
        let src = try writePNG(named: "narrow", width: 1000, height: 100)
        let out = workDir.appendingPathComponent("narrow-out.webp")
        let r = try await compress(src, format: .webp, output: out, maxWidth: 1200)
        XCTAssertNil(r.resize)
    }

    /// Replace original with the same format: the source must be byte-identical afterwards and the
    /// result staged elsewhere, so a "no gain" result can be thrown away safely.
    func testOutputOverSourceIsStaged() async throws {
        let src = try writePNG(named: "same", width: 200, height: 200)
        let before = try Data(contentsOf: src)
        let r = try await compress(src, format: .png, output: src, maxWidth: nil)
        XCTAssertEqual(try Data(contentsOf: src), before)
        XCTAssertEqual(r.stagedDestinationURL?.standardizedFileURL, src.standardizedFileURL)
        XCTAssertNotEqual(r.outputURL.standardizedFileURL, src.standardizedFileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: r.outputURL.path))
        try? FileManager.default.removeItem(at: r.outputURL)
    }

    // MARK: - Helpers

    private func compress(_ source: URL, format: CompressionFormat, output: URL, maxWidth: Int?) async throws -> DinkyImageCompressionResult {
        try await DinkyImageCompression(binDirectory: bin).compress(
            source: source,
            format: format,
            goals: CompressionGoals(maxWidth: maxWidth),
            stripMetadata: true,
            outputURL: output,
            parallelCompressionLimit: 1
        )
    }

    private func pixelSize(_ url: URL) throws -> CGSize {
        let src = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let props = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any])
        let w = try XCTUnwrap(props[kCGImagePropertyPixelWidth] as? Int)
        let h = try XCTUnwrap(props[kCGImagePropertyPixelHeight] as? Int)
        return CGSize(width: w, height: h)
    }

    private func writePNG(named name: String, width: Int, height: Int) throws -> URL {
        let ctx = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        for x in stride(from: 0, to: width, by: 10) {
            ctx.setFillColor(red: CGFloat(x % 255) / 255, green: 0.4, blue: 0.6, alpha: 1)
            ctx.fill(CGRect(x: x, y: 0, width: 10, height: height))
        }
        let image = try XCTUnwrap(ctx.makeImage())
        let url = workDir.appendingPathComponent("\(name).png")
        let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return url
    }
}
