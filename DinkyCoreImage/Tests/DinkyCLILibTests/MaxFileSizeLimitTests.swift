import CoreGraphics
import DinkyCoreImage
import DinkyCoreShared
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest

/// "Limit file size" is a ceiling. It used to be treated as a size to fill — searching for the
/// highest quality under the cap — so a roomy limit produced files bigger than no limit at all,
/// and bigger than the original, which then got discarded as "no saving".
final class MaxFileSizeLimitTests: XCTestCase {

    private var bin: URL!
    private var workDir: URL!

    override func setUpWithError() throws {
        guard let bin = DinkyEncoderPath.resolveBinDirectory() else {
            throw XCTSkip("Encoders not available in this environment.")
        }
        self.bin = bin
        workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dinky-maxsize-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let workDir { try? FileManager.default.removeItem(at: workDir) }
    }

    func testRoomyLimitGivesSameResultAsNoLimit() async throws {
        let photo = try writePhotoLikePNG(named: "photo")
        let unlimited = try await compressedSize(photo, content: .photo, limitKB: nil)
        let roomy = try await compressedSize(photo, content: .photo, limitKB: 100_000)
        XCTAssertEqual(roomy, unlimited)
    }

    func testReachableLimitIsMet() async throws {
        let photo = try writePhotoLikePNG(named: "photo")
        let unlimited = try await compressedSize(photo, content: .photo, limitKB: nil)
        let capKB = Int(unlimited / 1024 / 2)
        let limited = try await compressedSize(photo, content: .photo, limitKB: capKB)
        XCTAssertLessThanOrEqual(limited, Int64(capKB) * 1024)
    }

    /// When the cap can't be met, the smallest attempt is kept. Falling back to lossy WebP at the
    /// floor quality made busy graphics several times *larger* than near-lossless with no limit.
    func testUnreachableLimitNeverExceedsNoLimit() async throws {
        let graphic = try writeBusyGraphicPNG(named: "graphic")
        let unlimited = try await compressedSize(graphic, content: .graphic, limitKB: nil)
        let impossible = try await compressedSize(graphic, content: .graphic, limitKB: 1)
        XCTAssertLessThanOrEqual(impossible, unlimited)
    }

    // MARK: - Helpers

    private func compressedSize(_ source: URL, content: ContentType, limitKB: Int?) async throws -> Int64 {
        let out = workDir.appendingPathComponent("\(source.deletingPathExtension().lastPathComponent)-\(UUID().uuidString).webp")
        let r = try await DinkyImageCompression(binDirectory: bin).compress(
            source: source,
            format: .webp,
            goals: CompressionGoals(maxFileSizeKB: limitKB),
            stripMetadata: true,
            outputURL: out,
            originalsAction: .keep,
            backupFolderURL: nil,
            isURLDownloadSource: false,
            smartQuality: false,
            contentTypeHint: content.rawValue,
            preclassifiedContent: content,
            parallelCompressionLimit: 1,
            collisionNamingStyle: .finderDuplicate,
            collisionCustomPattern: "",
            qualityOverride: nil,
            chromaSubsampling: .auto,
            webpLossless: false,
            pngOutputMode: .lossless,
            progressHandler: nil
        )
        return r.outputSize
    }

    /// Smooth gradients plus grain, so lossy quality has real size to trade.
    private func writePhotoLikePNG(named name: String) throws -> URL {
        try writePNG(named: name, width: 640, height: 480) { ctx, w, h in
            var rng = SystemRandomNumberGenerator()
            for y in 0..<h {
                for x in 0..<w {
                    let n = CGFloat(Int.random(in: -14...14, using: &rng)) / 255
                    ctx.setFillColor(red: CGFloat(x) / CGFloat(w) * 0.8 + 0.1 + n,
                                     green: CGFloat(y) / CGFloat(h) * 0.7 + 0.15 + n,
                                     blue: 0.55 - CGFloat(x) / CGFloat(w) * 0.3 + n, alpha: 1)
                    ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
    }

    /// Many hard-edged flat blocks: near-lossless handles these far better than low-quality lossy.
    private func writeBusyGraphicPNG(named name: String) throws -> URL {
        try writePNG(named: name, width: 640, height: 480) { ctx, w, h in
            ctx.setFillColor(red: 0.98, green: 0.98, blue: 0.98, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            let palette: [(CGFloat, CGFloat, CGFloat)] = [(0.1, 0.35, 0.8), (0.9, 0.25, 0.25), (0.15, 0.65, 0.35), (0.12, 0.12, 0.12)]
            var rng = SystemRandomNumberGenerator()
            for _ in 0..<600 {
                let c = palette.randomElement(using: &rng)!
                ctx.setFillColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
                ctx.fill(CGRect(x: Int.random(in: 0..<w, using: &rng), y: Int.random(in: 0..<h, using: &rng),
                                width: Int.random(in: 4...80, using: &rng), height: Int.random(in: 4...40, using: &rng)))
            }
        }
    }

    private func writePNG(named name: String, width: Int, height: Int, draw: (CGContext, Int, Int) -> Void) throws -> URL {
        let ctx = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        draw(ctx, width, height)
        let image = try XCTUnwrap(ctx.makeImage())
        let url = workDir.appendingPathComponent("\(name).png")
        let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return url
    }
}
