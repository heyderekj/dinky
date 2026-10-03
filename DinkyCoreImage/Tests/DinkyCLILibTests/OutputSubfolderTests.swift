@testable import DinkyCoreShared
import XCTest

/// The subfolder name is typed by the user and then joined onto the destination directory, so it
/// has to stay a single, harmless path component.
final class OutputSubfolderTests: XCTestCase {

    func testPlainNamePassesThrough() {
        XCTAssertEqual(CompressionPreset.sanitizedOutputSubfolder("compressed-a"), "compressed-a")
    }

    func testWhitespaceIsTrimmed() {
        XCTAssertEqual(CompressionPreset.sanitizedOutputSubfolder("  compressed-webp  "), "compressed-webp")
    }

    func testEmptyAndBlankAreNil() {
        XCTAssertNil(CompressionPreset.sanitizedOutputSubfolder(""))
        XCTAssertNil(CompressionPreset.sanitizedOutputSubfolder("   "))
    }

    func testNestedPathIsFlattenedToFirstComponent() {
        XCTAssertEqual(CompressionPreset.sanitizedOutputSubfolder("a/b/c"), "a")
        XCTAssertEqual(CompressionPreset.sanitizedOutputSubfolder("a\\b"), "a")
    }

    /// Output must never be able to climb out of the destination folder.
    func testParentTraversalIsRejected() {
        XCTAssertNil(CompressionPreset.sanitizedOutputSubfolder(".."))
        XCTAssertNil(CompressionPreset.sanitizedOutputSubfolder("../.."))
        XCTAssertEqual(CompressionPreset.sanitizedOutputSubfolder("../escape"), "escape")
    }

    func testAbsolutePathIsRejectedAsRoot() {
        XCTAssertEqual(CompressionPreset.sanitizedOutputSubfolder("/etc/passwd"), "etc")
    }

    func testCurrentDirectoryIsRejected() {
        XCTAssertNil(CompressionPreset.sanitizedOutputSubfolder("."))
    }

    func testOverlongNameIsTruncated() {
        let long = String(repeating: "x", count: 250)
        XCTAssertEqual(CompressionPreset.sanitizedOutputSubfolder(long)?.count, 100)
    }
}
