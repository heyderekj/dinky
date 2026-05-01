@testable import DinkyCLILib
import DinkyCoreImage
import Foundation
import XCTest

final class MakeFixturesCommandTests: XCTestCase {
    func testParseDefaults() throws {
        let c = try DinkyMakeFixturesCommand.parseArgs([])
        XCTAssertNil(c.outputDir)
        XCTAssertEqual(c.types, Set(DinkyMakeFixturesCommand.FixtureMediaType.allCases))
        XCTAssertEqual(c.count, 1)
        XCTAssertEqual(c.seed, 0)
        XCTAssertFalse(c.overwrite)
        XCTAssertFalse(c.json)
    }

    func testParseTypesCountSeedOutput() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("dinky-make-fixtures-parse-\(UUID().uuidString)", isDirectory: true)
        let c = try DinkyMakeFixturesCommand.parseArgs([
            "--output-dir", tmp.path,
            "--types", "pdf,video",
            "--count", "2",
            "--seed", "99",
            "--overwrite",
            "--json",
        ])
        XCTAssertEqual(c.outputDir?.standardizedFileURL.path, tmp.standardizedFileURL.path)
        XCTAssertEqual(c.types, Set([DinkyMakeFixturesCommand.FixtureMediaType.pdf, .video]))
        XCTAssertEqual(c.count, 2)
        XCTAssertEqual(c.seed, 99)
        XCTAssertTrue(c.overwrite)
        XCTAssertTrue(c.json)
    }

    func testParseRejectBadCount() {
        XCTAssertThrowsError(try DinkyMakeFixturesCommand.parseArgs(["--count", "0"]))
        XCTAssertThrowsError(try DinkyMakeFixturesCommand.parseArgs(["--count", "99"]))
    }

    func testSmokeWritesManifestAndMedia() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dinky-fixtures-smoke-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let (code, n) = await DinkyMakeFixturesCommand.run([
            "--output-dir", dir.path,
            "--types", "images,video,pdf",
            "--count", "1",
            "--seed", "1",
            "--overwrite",
        ])
        XCTAssertEqual(code, 0)
        XCTAssertGreaterThan(n, 0)

        let manifestURL = dir.appendingPathComponent("manifest.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: manifestURL.path))

        let data = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(DinkyMakeFixturesCommand.FixtureManifest.self, from: data)
        XCTAssertEqual(manifest.schema, DinkyMakeFixturesCommand.manifestSchema)
        XCTAssertEqual(manifest.outputDirectory, dir.standardizedFileURL.path)

        let written = manifest.entries.filter { $0.bytes > 0 }.map(\.path)
        XCTAssertFalse(written.isEmpty)

        let hasPDF = manifest.entries.contains {
            $0.family == "pdf" && $0.format == "pdf" && $0.bytes > 0 && $0.note.localizedCaseInsensitiveContains("text")
        }
        XCTAssertTrue(hasPDF, "expected a text-heavy PDF entry")

        let hasScan = manifest.entries.contains {
            $0.family == "pdf" && $0.format == "pdf" && $0.bytes > 0 && $0.note.localizedCaseInsensitiveContains("scan")
        }
        XCTAssertTrue(hasScan, "expected a scan-like PDF entry")

        let hasMov = manifest.entries.contains { $0.family == "video" && $0.format == "mov" && $0.bytes > 0 }
        let hasMp4 = manifest.entries.contains { $0.family == "video" && $0.format == "mp4" && $0.bytes > 0 }
        XCTAssertTrue(hasMov && hasMp4)

        let hasPng = manifest.entries.contains { $0.family == "images" && $0.format == "png" && $0.bytes > 0 }
        XCTAssertTrue(hasPng)

        if DinkyEncoderPath.resolveBinDirectory() != nil {
            let hasWebp = manifest.entries.contains { $0.family == "images" && $0.format == "webp" && $0.bytes > 0 }
            let hasAvif = manifest.entries.contains { $0.family == "images" && $0.format == "avif" && $0.bytes > 0 }
            XCTAssertTrue(hasWebp, "when encoders exist, webp should be written")
            XCTAssertTrue(hasAvif, "when encoders exist, avif should be written")
        } else {
            let skippedWebp = manifest.entries.contains {
                $0.family == "images" && $0.format == "webp" && $0.note.localizedCaseInsensitiveContains("skipped")
            }
            XCTAssertTrue(skippedWebp)
        }
    }
}
