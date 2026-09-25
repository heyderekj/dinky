@testable import DinkyCLILib
import XCTest

final class ServeArgumentParserTests: XCTestCase {
    private let pinned = "pinned-token-0123456789"

    func testDefaults() throws {
        let o = try DinkyServeCommand.parseArgs([], environment: [:])
        XCTAssertEqual(o.port, 17381)
        XCTAssertNil(o.token)
        XCTAssertEqual(o.tokenSource, .generated)
    }

    func testPort() throws {
        XCTAssertEqual(try DinkyServeCommand.parseArgs(["--port", "8080"], environment: [:]).port, 8080)
        for bad in [["--port", "0"], ["--port", "65536"], ["--port", "abc"], ["--port", "-1"], ["--port"]] {
            XCTAssertThrowsError(try DinkyServeCommand.parseArgs(bad, environment: [:]), "\(bad)")
        }
    }

    func testUnknownOptionAndHelpThrow() {
        XCTAssertThrowsError(try DinkyServeCommand.parseArgs(["--nope"], environment: [:])) { err in
            XCTAssertEqual((err as? DinkyCLIParseError)?.message, "unknown option: --nope")
        }
        XCTAssertThrowsError(try DinkyServeCommand.parseArgs(["--help"], environment: [:]))
        XCTAssertThrowsError(try DinkyServeCommand.parseArgs(["--token"], environment: [:]))
    }

    func testTokenSources() throws {
        let env = try DinkyServeCommand.parseArgs([], environment: ["DINKY_SERVE_TOKEN": pinned])
        XCTAssertEqual(env.token, pinned)
        XCTAssertEqual(env.tokenSource, .environment)

        let flag = try DinkyServeCommand.parseArgs(["--token", "flag-token-0123456789"], environment: ["DINKY_SERVE_TOKEN": pinned])
        XCTAssertEqual(flag.token, "flag-token-0123456789")
        XCTAssertEqual(flag.tokenSource, .flag)

        let empty = try DinkyServeCommand.parseArgs([], environment: ["DINKY_SERVE_TOKEN": ""])
        XCTAssertNil(empty.token)
        XCTAssertEqual(empty.tokenSource, .generated)
    }

    func testInvalidTokensThrowWithoutEchoingValue() {
        for bad in ["short-token-123", "has a space in the token", "tøken-0123456789abcdef", "quote\"0123456789abcdef"] {
            XCTAssertThrowsError(try DinkyServeCommand.parseArgs(["--token", bad], environment: [:])) { err in
                XCTAssertFalse((err as? DinkyCLIParseError)?.message.contains(bad) ?? true, bad)
            }
            XCTAssertThrowsError(try DinkyServeCommand.parseArgs([], environment: ["DINKY_SERVE_TOKEN": bad])) { err in
                XCTAssertFalse((err as? DinkyCLIParseError)?.message.contains(bad) ?? true, bad)
            }
        }
    }

    func testBanner() {
        let generated = DinkyServeCommand.banner(port: 17381, ipv6: true, token: "abc123", source: .generated)
        XCTAssertTrue(generated.contains("http://127.0.0.1:17381 and http://[::1]:17381"))
        XCTAssertTrue(generated.contains("Bearer abc123"))

        let pinnedBanner = DinkyServeCommand.banner(port: 17381, ipv6: false, token: pinned, source: .environment)
        XCTAssertFalse(pinnedBanner.contains(pinned))
        XCTAssertTrue(pinnedBanner.contains("<your DINKY_SERVE_TOKEN>"))
        XCTAssertFalse(pinnedBanner.contains("[::1]"))
        XCTAssertFalse(DinkyServeCommand.banner(port: 17381, ipv6: true, token: pinned, source: .flag).contains(pinned))
    }
}
