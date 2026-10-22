import DinkyCLILib
import DinkyCoreImage
import XCTest

final class ArgumentParserTests: XCTestCase {
    func testPositionalFiles() throws {
        let r = try DinkyCompressArgParser.parse(["a.png", "b.jpg"])
        XCTAssertEqual(r.options.format, "auto")
        XCTAssertEqual(r.paths, ["a.png", "b.jpg"])
        XCTAssertTrue(r.preset.isEmpty)
    }

    func testDoubleDash() throws {
        let r = try DinkyCompressArgParser.parse(["--format", "webp", "--", "-weird name.png"])
        XCTAssertEqual(r.options.format, "webp")
        XCTAssertEqual(r.paths, ["-weird name.png"])
    }

    func testFlags() throws {
        let r = try DinkyCompressArgParser.parse([
            "-f", "avif", "-w", "800", "-q", "90", "-o", "/tmp/out", "--max-size-kb", "200",
            "--no-smart-quality", "--json", "-j", "4", "--strip", "in.png",
        ])
        let o = r.options
        XCTAssertEqual(o.format, "avif")
        XCTAssertEqual(o.maxWidth, 800)
        XCTAssertEqual(o.quality, 90)
        XCTAssertEqual(o.outputDir?.path, "/tmp/out")
        XCTAssertEqual(o.maxFileSizeKB, 200)
        XCTAssertFalse(o.smartQuality)
        XCTAssertTrue(o.json)
        XCTAssertEqual(o.parallelLimit, 4)
        XCTAssertTrue(o.stripMetadata)
        XCTAssertEqual(r.paths, ["in.png"])
        XCTAssertTrue(r.explicit.contains("quality"))
    }

    func testScaleFlag() throws {
        let r = try DinkyCompressArgParser.parse(["--scale", "50%", "in.png"])
        XCTAssertEqual(r.options.scalePercent, 50)
        XCTAssertTrue(r.explicit.contains("scale"))
        XCTAssertEqual(try DinkyCompressArgParser.parse(["--scale", "25", "in.png"]).options.scalePercent, 25)
    }

    func testScaleOutOfRangeThrows() {
        XCTAssertThrowsError(try DinkyCompressArgParser.parse(["--scale", "0", "in.png"]))
        XCTAssertThrowsError(try DinkyCompressArgParser.parse(["--scale", "101", "in.png"]))
    }

    func testHelpThrows() {
        XCTAssertThrowsError(try DinkyCompressArgParser.parse(["--help"])) { err in
            let e = err as? DinkyCLIParseError
            XCTAssertTrue(e?.message.contains("help") == true)
        }
    }

    func testUnknownOption() {
        XCTAssertThrowsError(try DinkyCompressArgParser.parse(["--nope"])) { err in
            let e = err as? DinkyCLIParseError
            XCTAssertEqual(e?.message, "unknown option: --nope")
        }
    }

    func testPresetFlagsParsed() throws {
        let r = try DinkyCompressArgParser.parse(["--preset", "Web", "--preset-file", "/tmp/p.json", "a.png"])
        XCTAssertEqual(r.preset.name, "Web")
        XCTAssertEqual(r.preset.file, "/tmp/p.json")
    }
}
