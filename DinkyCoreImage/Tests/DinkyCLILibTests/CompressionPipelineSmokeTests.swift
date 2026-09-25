import DinkyCoreImage
import DinkyCLILib
import DinkyCoreShared
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest

/// 1×1 RGBA PNG (minimal).
private let tinyPNGData: [UInt8] = [
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
    0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
    0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
    0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]

final class CompressionPipelineSmokeTests: XCTestCase {
    func testEncodersRequiredForCompression() throws {
        guard let bin = DinkyEncoderPath.resolveBinDirectory() else {
            throw XCTSkip("No encoder directory (DINKY_BIN, ./bin, or Homebrew cwebp+avifenc+oxipng).")
        }
        XCTAssertTrue(DinkyEncoderPath.isValidEncoderDir(bin))
    }

    func testCompressTinyPNGToWebP() async throws {
        guard let bin = DinkyEncoderPath.resolveBinDirectory() else {
            throw XCTSkip("Encoders not available in this environment.")
        }
        let temp = FileManager.default.temporaryDirectory
        let id = UUID().uuidString
        let inURL = temp.appendingPathComponent("dinky-test-\(id).png", isDirectory: false)
        let outDir = temp.appendingPathComponent("dinky-test-out-\(id)", isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        try Data(tinyPNGData).write(to: inURL)
        defer {
            try? FileManager.default.removeItem(at: inURL)
            try? FileManager.default.removeItem(at: outDir)
        }

        let engine = DinkyImageCompression(binDirectory: bin)
        let desiredOut = outDir.appendingPathComponent("dinky-test-\(id).webp", isDirectory: false)
        let r = try await engine.compress(
            source: inURL,
            format: .webp,
            goals: CompressionGoals(),
            stripMetadata: true,
            outputURL: desiredOut,
            smartQuality: false,
            contentTypeHint: "auto",
            preclassifiedContent: nil,
            parallelCompressionLimit: 1,
            collisionNamingStyle: .finderDuplicate,
            collisionCustomPattern: "",
            qualityOverride: 80,
            progressHandler: nil
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: r.outputURL.path))
        XCTAssertGreaterThan(r.outputSize, 0)
        XCTAssertLessThanOrEqual(r.outputSize, r.originalSize + 1000) // tiny PNG, WebP may be small
    }

    func testCompressJPEGToPNG() async throws {
        guard let bin = DinkyEncoderPath.resolveBinDirectory() else {
            throw XCTSkip("Encoders not available in this environment.")
        }
        let temp = FileManager.default.temporaryDirectory
        let id = UUID().uuidString
        let inURL = temp.appendingPathComponent("dinky-test-\(id).jpg", isDirectory: false)
        let outDir = temp.appendingPathComponent("dinky-test-out-\(id)", isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        try writeTinyJPEG(to: inURL)
        defer {
            try? FileManager.default.removeItem(at: inURL)
            try? FileManager.default.removeItem(at: outDir)
        }

        let engine = DinkyImageCompression(binDirectory: bin)
        let desiredOut = outDir.appendingPathComponent("dinky-test-\(id).png", isDirectory: false)
        let r = try await engine.compress(
            source: inURL,
            format: .png,
            goals: CompressionGoals(),
            stripMetadata: true,
            outputURL: desiredOut,
            smartQuality: false,
            contentTypeHint: "auto",
            preclassifiedContent: nil,
            parallelCompressionLimit: 1,
            collisionNamingStyle: .finderDuplicate,
            collisionCustomPattern: "",
            qualityOverride: nil,
            progressHandler: nil
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: r.outputURL.path))
        XCTAssertEqual(r.outputURL.pathExtension.lowercased(), "png")
        XCTAssertGreaterThan(r.outputSize, 0)
    }

    func testCLICompressWithOptionsMatchesExitAllSuccess() async throws {
        guard DinkyEncoderPath.resolveBinDirectory() != nil else {
            throw XCTSkip("Encoders not available.")
        }
        let temp = FileManager.default.temporaryDirectory
        let id = UUID().uuidString
        let inURL = temp.appendingPathComponent("dinky-cli-\(id).png", isDirectory: false)
        try Data(tinyPNGData).write(to: inURL)
        defer { try? FileManager.default.removeItem(at: inURL) }

        var opts = DinkyCompressOptions()
        opts.format = "webp"
        opts.quality = 80
        opts.smartQuality = false
        opts.json = true
        let (code, results) = await DinkyCompressCommand.runWithOptions(opts, paths: [inURL.path])
        XCTAssertEqual(code, 0, "stderr: check encoder paths — \(String(describing: results.first?.error))")
        XCTAssertEqual(results.count, 1)
        XCTAssertNil(results[0].error)
        if let out = results[0].output { try? FileManager.default.removeItem(at: URL(fileURLWithPath: out)) }
    }

    func testLosslessWebPProducesOutput() async throws {
        guard let bin = DinkyEncoderPath.resolveBinDirectory() else {
            throw XCTSkip("Encoders not available in this environment.")
        }
        let temp = FileManager.default.temporaryDirectory
        let id = UUID().uuidString
        let inURL = temp.appendingPathComponent("dinky-lossless-\(id).png", isDirectory: false)
        let outDir = temp.appendingPathComponent("dinky-lossless-out-\(id)", isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        try Data(tinyPNGData).write(to: inURL)
        defer {
            try? FileManager.default.removeItem(at: inURL)
            try? FileManager.default.removeItem(at: outDir)
        }

        let engine = DinkyImageCompression(binDirectory: bin)
        let desiredOut = outDir.appendingPathComponent("dinky-lossless-\(id).webp", isDirectory: false)
        let r = try await engine.compress(
            source: inURL,
            format: .webp,
            goals: CompressionGoals(),
            stripMetadata: true,
            outputURL: desiredOut,
            smartQuality: false,
            contentTypeHint: "auto",
            preclassifiedContent: nil,
            parallelCompressionLimit: 1,
            collisionNamingStyle: .finderDuplicate,
            collisionCustomPattern: "",
            qualityOverride: nil,
            chromaSubsampling: .auto,
            webpLossless: true,
            pngOutputMode: .lossless,
            progressHandler: nil
        )
        XCTAssertTrue(r.appliedWebpLossless)
        XCTAssertTrue(FileManager.default.fileExists(atPath: r.outputURL.path))
        XCTAssertGreaterThan(r.outputSize, 0)
    }

    func testAvifChroma444DiffersFrom420() async throws {
        guard let bin = DinkyEncoderPath.resolveBinDirectory() else {
            throw XCTSkip("Encoders not available in this environment.")
        }
        let temp = FileManager.default.temporaryDirectory
        let id = UUID().uuidString
        let inURL = temp.appendingPathComponent("dinky-chroma-\(id).png", isDirectory: false)
        let outDir = temp.appendingPathComponent("dinky-chroma-out-\(id)", isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        try writeFlatGraphicPNG(to: inURL, width: 64, height: 64)
        defer {
            try? FileManager.default.removeItem(at: inURL)
            try? FileManager.default.removeItem(at: outDir)
        }

        let engine = DinkyImageCompression(binDirectory: bin)
        func compress(chroma: ChromaSubsampling) async throws -> DinkyImageCompressionResult {
            let out = outDir.appendingPathComponent("chroma-\(chroma.rawValue)-\(id).avif")
            return try await engine.compress(
                source: inURL,
                format: .avif,
                goals: CompressionGoals(),
                stripMetadata: true,
                outputURL: out,
                smartQuality: false,
                contentTypeHint: "graphic",
                preclassifiedContent: .graphic,
                parallelCompressionLimit: 1,
                collisionNamingStyle: .finderDuplicate,
                collisionCustomPattern: "",
                qualityOverride: 75,
                chromaSubsampling: chroma,
                webpLossless: false,
                pngOutputMode: .lossless,
                progressHandler: nil
            )
        }

        let r420 = try await compress(chroma: .yuv420)
        let r444 = try await compress(chroma: .yuv444)
        XCTAssertEqual(r420.appliedChromaSubsampling, "420")
        XCTAssertEqual(r444.appliedChromaSubsampling, "444")
        XCTAssertNotEqual(r420.outputSize, r444.outputSize)
    }

    func testOptimizedPNGOnFlatGraphic() async throws {
        guard let bin = DinkyEncoderPath.resolveBinDirectory() else {
            throw XCTSkip("Encoders not available in this environment.")
        }
        let temp = FileManager.default.temporaryDirectory
        let id = UUID().uuidString
        let inURL = temp.appendingPathComponent("dinky-pngopt-\(id).png", isDirectory: false)
        let outDir = temp.appendingPathComponent("dinky-pngopt-out-\(id)", isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        try writeFlatGraphicPNG(to: inURL, width: 32, height: 32)
        defer {
            try? FileManager.default.removeItem(at: inURL)
            try? FileManager.default.removeItem(at: outDir)
        }

        let engine = DinkyImageCompression(binDirectory: bin)
        let desiredOut = outDir.appendingPathComponent("dinky-pngopt-\(id).png", isDirectory: false)
        let r = try await engine.compress(
            source: inURL,
            format: .png,
            goals: CompressionGoals(),
            stripMetadata: true,
            outputURL: desiredOut,
            smartQuality: false,
            contentTypeHint: "graphic",
            preclassifiedContent: .graphic,
            parallelCompressionLimit: 1,
            collisionNamingStyle: .finderDuplicate,
            collisionCustomPattern: "",
            qualityOverride: nil,
            chromaSubsampling: .auto,
            webpLossless: false,
            pngOutputMode: .optimized,
            progressHandler: nil
        )
        XCTAssertEqual(r.appliedPngOutputMode, PNGOutputMode.optimized.rawValue)
        XCTAssertTrue(FileManager.default.fileExists(atPath: r.outputURL.path))
        XCTAssertLessThanOrEqual(r.outputSize, r.originalSize)
    }
}

private func writeTinyJPEG(to url: URL) throws {
    guard let src = CGImageSourceCreateWithData(Data(tinyPNGData) as CFData, nil),
          let cgImage = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
        throw NSError(domain: "CompressionPipelineSmokeTests", code: 1)
    }
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
        throw NSError(domain: "CompressionPipelineSmokeTests", code: 2)
    }
    CGImageDestinationAddImage(dest, cgImage, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
    guard CGImageDestinationFinalize(dest) else {
        throw NSError(domain: "CompressionPipelineSmokeTests", code: 3)
    }
}

/// Opaque PNG with a small set of flat colors (≤256) for palette / chroma tests.
private func writeFlatGraphicPNG(to url: URL, width: Int, height: Int) throws {
    let colors: [(UInt8, UInt8, UInt8)] = [
        (220, 40, 40), (40, 120, 220), (40, 180, 80), (240, 200, 40),
    ]
    var pixels = [UInt8]()
    pixels.reserveCapacity(width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let c = colors[(x / 8 + y / 8) % colors.count]
            pixels.append(c.0)
            pixels.append(c.1)
            pixels.append(c.2)
            pixels.append(255)
        }
    }
    let cs = CGColorSpaceCreateDeviceRGB()
    let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
    let pixelData = Data(pixels)
    guard let provider = CGDataProvider(data: pixelData as CFData),
          let cg = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: cs,
            bitmapInfo: CGBitmapInfo(rawValue: info),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
          ) else {
        throw NSError(domain: "CompressionPipelineSmokeTests", code: 4)
    }
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "CompressionPipelineSmokeTests", code: 6)
    }
    CGImageDestinationAddImage(dest, cg, nil)
    guard CGImageDestinationFinalize(dest) else {
        throw NSError(domain: "CompressionPipelineSmokeTests", code: 7)
    }
}
