import DinkyCoreShared
import XCTest

final class SubprocessRunnerTests: XCTestCase {

    /// Reading stderr only after exit deadlocked once a tool wrote more than a pipe buffer.
    func testLargeOutputOnBothStreamsDoesNotHang() async throws {
        let script = """
        head -c 300000 /dev/zero | tr '\\0' 'o'
        head -c 300000 /dev/zero | tr '\\0' 'e' >&2
        echo tail-marker >&2
        exit 3
        """
        let out = try await SubprocessRunner.run(URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", script])
        XCTAssertEqual(out.status, 3)
        XCTAssertTrue(out.stderr.hasSuffix("tail-marker\n"))
        XCTAssertLessThanOrEqual(out.stderr.utf8.count, 64 * 1024)
    }

    func testSuccess() async throws {
        let out = try await SubprocessRunner.run(URL(fileURLWithPath: "/usr/bin/true"), arguments: [])
        XCTAssertEqual(out.status, 0)
        XCTAssertEqual(out.stderr, "")
    }

    func testMissingExecutableThrows() async {
        do {
            _ = try await SubprocessRunner.run(URL(fileURLWithPath: "/nonexistent/tool"), arguments: [])
            XCTFail("expected an error")
        } catch {}
    }
}
