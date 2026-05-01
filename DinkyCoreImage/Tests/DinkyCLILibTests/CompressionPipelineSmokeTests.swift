import DinkyCoreImage
import DinkyCLILib
import Foundation
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
            originalsAction: .keep,
            backupFolderURL: nil,
            isURLDownloadSource: false,
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
}
