import DinkyCLILib
import XCTest

final class ArgumentParserTests: XCTestCase {
    func testPositionalFiles() throws {
        let (o, files) = try DinkyCompressArgParser.parse(["a.png", "b.jpg"])
        XCTAssertEqual(o.format, "auto")
        XCTAssertEqual(files, ["a.png", "b.jpg"])
    }

    func testDoubleDash() throws {
        let (o, files) = try DinkyCompressArgParser.parse(["--format", "webp", "--", "-weird name.png"])
        XCTAssertEqual(o.format, "webp")
        XCTAssertEqual(files, ["-weird name.png"])
    }

    func testFlags() throws {
        let (o, files) = try DinkyCompressArgParser.parse([
            "-f", "avif", "-w", "800", "-q", "90", "-o", "/tmp/out", "--max-size-kb", "200",
            "--no-smart-quality", "--json", "-j", "4", "--strip", "in.png",
        ])
        XCTAssertEqual(o.format, "avif")
        XCTAssertEqual(o.maxWidth, 800)
        XCTAssertEqual(o.quality, 90)
        XCTAssertEqual(o.outputDir?.path, "/tmp/out")
        XCTAssertEqual(o.maxFileSizeKB, 200)
        XCTAssertFalse(o.smartQuality)
        XCTAssertTrue(o.json)
        XCTAssertEqual(o.parallelLimit, 4)
        XCTAssertTrue(o.stripMetadata)
        XCTAssertEqual(files, ["in.png"])
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
}
