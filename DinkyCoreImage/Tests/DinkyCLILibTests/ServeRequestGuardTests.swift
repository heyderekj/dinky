@testable import DinkyCLILib
import XCTest

final class ServeRequestGuardTests: XCTestCase {
    private let port: UInt16 = 17381
    private let token = "0123456789abcdef0123456789abcdef"

    private func raw(_ requestLine: String, _ headers: [String]) -> String {
        ([requestLine] + headers).joined(separator: "\r\n") + "\r\n"
    }

    /// Status the guard produces (`nil` = allowed), with 400 for an unparseable head.
    private func status(_ requestLine: String, _ headers: [String], port: UInt16 = 17381) -> Int? {
        guard let head = DinkyServeRequestHead.parse(raw(requestLine, headers)) else { return 400 }
        return DinkyServeRequestGuard.check(head, port: port, token: token)?.status
    }

    /// Same as above for `POST /v1/compress`.
    private func status(_ headers: [String], port: UInt16 = 17381) -> Int? {
        status("POST /v1/compress HTTP/1.1", headers, port: port)
    }

    private var auth: String { "Authorization: Bearer \(token)" }
    private let json = "Content-Type: application/json"

    private func validPOST(host: String) -> [String] {
        ["Host: \(host)", auth, json]
    }

    // MARK: Parse

    func testParseExtractsRequestLineAndHeaders() throws {
        let head = try XCTUnwrap(DinkyServeRequestHead.parse(raw("GET /v1/health HTTP/1.1", ["HOST:  localhost:17381 \t", "X-A: 1", "x-a: 2"])))
        XCTAssertEqual(head.method, "GET")
        XCTAssertEqual(head.target, "/v1/health")
        XCTAssertEqual(head.values("Host"), ["localhost:17381"])
        XCTAssertEqual(head.values("x-a"), ["1", "2"])
        XCTAssertTrue(head.isHealthCheck)
    }

    func testParseRejectsMalformedHeads() {
        let bad: [String] = [
            "",
            raw("GET /v1/health", ["Host: localhost:17381"]),
            raw("GET  /v1/health HTTP/1.1", ["Host: localhost:17381"]),
            raw("GET /v1/health HTTP/2.0", ["Host: localhost:17381"]),
            raw("GET http://localhost:17381/v1/health HTTP/1.1", ["Host: localhost:17381"]),
            raw("OPTIONS * HTTP/1.1", ["Host: localhost:17381"]),
            raw("GET /v1/health HTTP/1.1", ["Host: localhost:17381", " folded"]),
            raw("GET /v1/health HTTP/1.1", ["Host: localhost:17381", "\tfolded"]),
            raw("GET /v1/health HTTP/1.1", ["Host : localhost:17381"]),
            raw("GET /v1/health HTTP/1.1", ["Host localhost:17381"]),
            raw("GET /v1/health HTTP/1.1", [": localhost:17381"]),
            raw("GET /v1/health HTTP/1.1", ["Host: localhost:17381\nOrigin: x"]),
            raw("GET /v1/health HTTP/1.1", ["Host: localhost:17381\rOrigin: x"]),
            raw("GET /v1/health HTTP/1.1", ["Host: localhost:17381\u{0}"]),
            raw("GET /v1/health HTTP/1.1", ["Host: ｌocalhost:17381"]),
            raw("GET /v1/health HTTP/1.1", ["Host: localhost:17381", "X-\u{212A}: 1"]),
        ]
        for text in bad {
            XCTAssertNil(DinkyServeRequestHead.parse(text), text.debugDescription)
        }
    }

    // MARK: Host

    func testAllowsLoopbackHosts() {
        for host in ["127.0.0.1:17381", "localhost:17381", "LocalHost:17381", "[::1]:17381", "localhost:017381"] {
            XCTAssertNil(status(validPOST(host: host)), host)
        }
        XCTAssertNil(status(["host: localhost:17381", auth, json]))
    }

    func testBareHostOnlyAllowedOnPort80() {
        for host in ["localhost", "127.0.0.1", "[::1]"] {
            XCTAssertNil(status(validPOST(host: host), port: 80), host)
            XCTAssertEqual(status(validPOST(host: host)), 403, host)
        }
    }

    func testMissingOrDuplicateHostIs400() {
        XCTAssertEqual(status([auth, json]), 400)
        XCTAssertEqual(status(["Host: localhost:17381", "Host: localhost:17381", auth, json]), 400)
        XCTAssertEqual(status(["Host: localhost:17381", "Host: evil.example:17381", auth, json]), 400)
    }

    func testRejectsForeignHosts() {
        let hosts = [
            "localhost:8080", "evil.example:17381", "192.168.1.187:17381",
            "localhost.:17381", "127.0.0.1.:17381", "localhost.evil.com:17381", "127.0.0.1.nip.io:17381",
            "127.1:17381", "127.0.0.2:17381", "0.0.0.0:17381",
            "[::ffff:127.0.0.1]:17381", "[0:0:0:0:0:0:0:1]:17381", "[::1%lo0]:17381", "::1:17381", "[::1", "[::1]x17381",
            "a@localhost:17381", "localhost:17381:1", "localhost:+17381", "localhost:", "localhost:99999", "",
        ]
        for host in hosts {
            XCTAssertEqual(status(validPOST(host: host)), 403, host)
        }
    }

    // MARK: Origin

    func testRejectsAnyOrigin() {
        for origin in ["https://evil.example", "null", "http://127.0.0.1:17381"] {
            XCTAssertEqual(status(validPOST(host: "127.0.0.1:17381") + ["Origin: \(origin)"]), 403, origin)
            XCTAssertEqual(status("GET /v1/health HTTP/1.1", ["Host: 127.0.0.1:17381", "Origin: \(origin)"]), 403, origin)
        }
        XCTAssertEqual(status(validPOST(host: "127.0.0.1:17381") + ["ORIGIN: https://evil.example"]), 403)
        XCTAssertEqual(status("OPTIONS /v1/compress HTTP/1.1", ["Host: 127.0.0.1:17381", "Origin: https://evil.example"]), 403)
    }

    // MARK: Token

    func testHealthNeedsNoToken() {
        XCTAssertNil(status("GET /v1/health HTTP/1.1", ["Host: 127.0.0.1:17381"]))
        XCTAssertNil(status("GET /v1/health?verbose=1 HTTP/1.1", ["Host: 127.0.0.1:17381"]))
    }

    func testEverythingElseNeedsToken() throws {
        let unauthenticated: [(String, [String])] = [
            ("POST /v1/compress HTTP/1.1", ["Host: 127.0.0.1:17381", json]),
            ("GET / HTTP/1.1", ["Host: 127.0.0.1:17381"]),
            ("GET /v1/healthz HTTP/1.1", ["Host: 127.0.0.1:17381"]),
            ("GET /v1/health/ HTTP/1.1", ["Host: 127.0.0.1:17381"]),
            ("POST /v1/health HTTP/1.1", ["Host: 127.0.0.1:17381", json]),
            ("HEAD /v1/health HTTP/1.1", ["Host: 127.0.0.1:17381"]),
            ("OPTIONS /v1/compress HTTP/1.1", ["Host: 127.0.0.1:17381"]),
        ]
        for (line, headers) in unauthenticated {
            let head = try XCTUnwrap(DinkyServeRequestHead.parse(raw(line, headers)))
            let rejection = DinkyServeRequestGuard.check(head, port: port, token: token)
            XCTAssertEqual(rejection?.status, 401, line)
            XCTAssertEqual(rejection?.headers["WWW-Authenticate"], "Bearer realm=\"dinky\"", line)
        }
    }

    func testRejectsBadTokens() {
        let badAuth = [
            "Authorization: Bearer wrong-token-wrong-token-wrong-tok",
            "Authorization: Bearer \(token)x",
            "Authorization: Bearer \(token.dropLast())",
            "Authorization: Basic \(token)",
            "Authorization: Bearer",
            "Authorization: Bearer ",
            "Authorization: \(token)",
        ]
        for header in badAuth {
            XCTAssertEqual(status(["Host: 127.0.0.1:17381", header, json]), 401, header)
        }
        XCTAssertEqual(status(["Host: 127.0.0.1:17381", auth, auth, json]), 401)
    }

    func testAcceptsBearerSchemeCaseInsensitively() {
        XCTAssertNil(status(["Host: 127.0.0.1:17381", "Authorization: bearer \(token)", json]))
        XCTAssertNil(status(["Host: 127.0.0.1:17381", "Authorization: BEARER   \(token)  ", json]))
    }

    // MARK: Content-Type

    func testPOSTRequiresJSONContentType() {
        for type in ["application/json", "Application/JSON; charset=utf-8", "application/json;charset=UTF-8"] {
            XCTAssertNil(status(["Host: 127.0.0.1:17381", auth, "Content-Type: \(type)"]), type)
        }
        for type in [
            "text/plain;charset=UTF-8", "application/x-www-form-urlencoded", "multipart/form-data; boundary=x",
            "application/jsonp", "application/json-patch+json", "",
        ] {
            XCTAssertEqual(status(["Host: 127.0.0.1:17381", auth, "Content-Type: \(type)"]), 415, type)
        }
        XCTAssertEqual(status(["Host: 127.0.0.1:17381", auth]), 415)
        XCTAssertEqual(status(["Host: 127.0.0.1:17381", auth, json, json]), 415)
    }

    // MARK: Order

    func testCheckOrder() {
        XCTAssertEqual(status(["Origin: https://evil.example", json]), 400)
        XCTAssertEqual(status(["Host: evil.example:17381", "Origin: https://evil.example"]), 403)
        XCTAssertEqual(status(["Host: 127.0.0.1:17381", "Origin: https://evil.example", "Content-Type: text/plain"]), 403)
        XCTAssertEqual(status(["Host: 127.0.0.1:17381", "Content-Type: text/plain"]), 401)
    }

    // MARK: Utilities

    func testConstantTimeEquals() {
        XCTAssertTrue(DinkyServeRequestGuard.constantTimeEquals("abc", "abc"))
        XCTAssertTrue(DinkyServeRequestGuard.constantTimeEquals("", ""))
        XCTAssertFalse(DinkyServeRequestGuard.constantTimeEquals("abc", "abd"))
        XCTAssertFalse(DinkyServeRequestGuard.constantTimeEquals("abc", "abcd"))
    }

    func testMakeToken() {
        let a = DinkyServeRequestGuard.makeToken()
        let b = DinkyServeRequestGuard.makeToken()
        XCTAssertEqual(a.count, 64)
        XCTAssertTrue(a.allSatisfy { "0123456789abcdef".contains($0) })
        XCTAssertTrue(DinkyServeRequestGuard.isValidToken(a))
        XCTAssertNotEqual(a, b)
    }
}
