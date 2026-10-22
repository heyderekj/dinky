import CoreGraphics
import DinkyCoreImage
import DinkyCoreShared
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest

/// JPEG output goes through ImageIO (no bundled encoder), for apps that can't open WebP or AVIF.
final class JPEGOutputTests: XCTestCase {

    private var bin: URL!
    private var workDir: URL!

    override func setUpWithError() throws {
        guard let bin = DinkyEncoderPath.resolveBinDirectory() else {
            throw XCTSkip("Encoders not available in this environment.")
        }
        self.bin = bin
        workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dinky-jpeg-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let workDir { try? FileManager.default.removeItem(at: workDir) }
    }

    func testFormatBasics() {
        XCTAssertEqual(CompressionFormat.jpeg.outputExtension, "jpg")
        XCTAssertEqual(CompressionFormat.jpeg.binaryName, "imageio")
    }

    func testPNGToJPEG() async throws {
        let src = try writePNG(named: "opaque", width: 400, height: 300, transparent: false)
        let out = workDir.appendingPathComponent("opaque.jpg")
        let r = try await compress(src, output: out)
        XCTAssertEqual(try imageType(r.outputURL), UTType.jpeg.identifier)
        XCTAssertEqual(try pixelSize(r.outputURL), CGSize(width: 400, height: 300))
    }

    func testTransparencyBecomesWhite() async throws {
        let src = try writePNG(named: "clear", width: 40, height: 40, transparent: true)
        let out = workDir.appendingPathComponent("clear.jpg")
        let r = try await compress(src, output: out)
        let (red, green, blue) = try firstPixelRGB(r.outputURL)
        XCTAssertGreaterThan(red, 240)
        XCTAssertGreaterThan(green, 240)
        XCTAssertGreaterThan(blue, 240)
    }

    func testWidthLimitApplies() async throws {
        let src = try writePNG(named: "wide", width: 2000, height: 1000, transparent: false)
        let out = workDir.appendingPathComponent("wide.jpg")
        let r = try await compress(src, output: out, goals: CompressionGoals(maxWidth: 500))
        XCTAssertEqual(try pixelSize(r.outputURL), CGSize(width: 500, height: 250))
    }

    // MARK: - Helpers

    private func compress(_ source: URL, output: URL, goals: CompressionGoals = CompressionGoals()) async throws -> DinkyImageCompressionResult {
        try await DinkyImageCompression(binDirectory: bin).compress(
            source: source,
            format: .jpeg,
            goals: goals,
            stripMetadata: true,
            outputURL: output,
            parallelCompressionLimit: 1
        )
    }

    private func imageType(_ url: URL) throws -> String? {
        let src = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return CGImageSourceGetType(src) as String?
    }

    private func pixelSize(_ url: URL) throws -> CGSize {
        let src = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let props = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any])
        let w = try XCTUnwrap(props[kCGImagePropertyPixelWidth] as? Int)
        let h = try XCTUnwrap(props[kCGImagePropertyPixelHeight] as? Int)
        return CGSize(width: w, height: h)
    }

    private func firstPixelRGB(_ url: URL) throws -> (UInt8, UInt8, UInt8) {
        let src = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
        var pixel = [UInt8](repeating: 0, count: 4)
        let ctx = try XCTUnwrap(CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return (pixel[0], pixel[1], pixel[2])
    }

    private func writePNG(named name: String, width: Int, height: Int, transparent: Bool) throws -> URL {
        let ctx = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: (transparent ? CGImageAlphaInfo.premultipliedLast : CGImageAlphaInfo.noneSkipLast).rawValue
        ))
        if !transparent {
            for x in stride(from: 0, to: width, by: 10) {
                ctx.setFillColor(red: CGFloat(x % 255) / 255, green: 0.4, blue: 0.6, alpha: 1)
                ctx.fill(CGRect(x: x, y: 0, width: 10, height: height))
            }
        }
        let image = try XCTUnwrap(ctx.makeImage())
        let url = workDir.appendingPathComponent("\(name).png")
        let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return url
    }
}
