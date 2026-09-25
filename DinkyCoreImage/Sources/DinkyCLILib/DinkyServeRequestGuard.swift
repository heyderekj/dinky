import Foundation

/// Request line and headers of one `dinky serve` request (everything before the blank line).
struct DinkyServeRequestHead: Equatable, Sendable {
    var method: String
    var target: String
    /// Lowercased header name → values in arrival order.
    var headers: [String: [String]]

    func values(_ name: String) -> [String] { headers[name.lowercased()] ?? [] }

    /// `GET /v1/health` — the only route that does not need the bearer token.
    var isHealthCheck: Bool {
        method == "GET" && (target == "/v1/health" || target.hasPrefix("/v1/health?"))
    }

    /// Strict HTTP/1.x head parser. ASCII only, CRLF line endings, no obs-fold; `nil` means 400.
    static func parse(_ head: String) -> DinkyServeRequestHead? {
        guard !head.isEmpty, head.utf8.allSatisfy({ $0 < 0x80 }) else { return nil }
        var lines = head.components(separatedBy: "\r\n")
        while lines.last == "" { lines.removeLast() }
        guard let requestLine = lines.first else { return nil }
        for line in lines where line.utf8.contains(where: { ($0 < 0x20 && $0 != 0x09) || $0 == 0x7F }) {
            return nil
        }

        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3,
              !parts[0].isEmpty, parts[0].allSatisfy(isTokenChar),
              parts[1].hasPrefix("/"),
              parts[2] == "HTTP/1.1" || parts[2] == "HTTP/1.0"
        else { return nil }

        var headers: [String: [String]] = [:]
        for line in lines.dropFirst() {
            guard let first = line.first, first != " ", first != "\t",
                  let colon = line.firstIndex(of: ":")
            else { return nil }
            let name = line[..<colon]
            guard !name.isEmpty, name.allSatisfy(isTokenChar) else { return nil }
            let value = trimSpaceAndTab(line[line.index(after: colon)...])
            headers[name.lowercased(), default: []].append(value)
        }
        return DinkyServeRequestHead(method: parts[0], target: parts[1], headers: headers)
    }

    private static func isTokenChar(_ c: Character) -> Bool {
        guard let a = c.asciiValue else { return false }
        switch a {
        case UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "A")...UInt8(ascii: "Z"):
            return true
        default:
            return "!#$%&'*+-.^_`|~".utf8.contains(a)
        }
    }
}

func trimSpaceAndTab<S: StringProtocol>(_ s: S) -> String {
    s.trimmingCharacters(in: CharacterSet(charactersIn: " \t"))
}

struct DinkyServeRejection: Equatable, Sendable {
    var status: Int
    /// Constant message; never echoes request data.
    var error: String
    var headers: [String: String] = [:]

    var body: String { "{\"error\":\"\(error)\"}" }
}

/// Request checks for `dinky serve`: Host allowlist (DNS rebinding), no `Origin` (browsers),
/// bearer token, and JSON-only POSTs (CSRF via form / no-cors bodies).
enum DinkyServeRequestGuard {
    static let tokenEnvironmentKey = "DINKY_SERVE_TOKEN"

    static func check(_ head: DinkyServeRequestHead, port: UInt16, token: String) -> DinkyServeRejection? {
        let hosts = head.values("host")
        guard hosts.count == 1 else {
            return DinkyServeRejection(status: 400, error: "missing or duplicate Host header")
        }
        guard isAllowedHost(hosts[0], port: port) else {
            return DinkyServeRejection(status: 403, error: "Host not allowed")
        }
        guard head.values("origin").isEmpty else {
            return DinkyServeRejection(status: 403, error: "Origin not allowed")
        }
        if !head.isHealthCheck, !isAuthorized(head.values("authorization"), token: token) {
            return DinkyServeRejection(
                status: 401,
                error: "missing or invalid token",
                headers: ["WWW-Authenticate": "Bearer realm=\"dinky\""]
            )
        }
        if head.method == "POST" {
            let types = head.values("content-type")
            guard types.count == 1, isJSONMediaType(types[0]) else {
                return DinkyServeRejection(status: 415, error: "Content-Type must be application/json")
            }
        }
        return nil
    }

    /// `localhost`, `127.0.0.1` or `[::1]` with the listening port (port may be omitted only on 80).
    static func isAllowedHost(_ value: String, port: UInt16) -> Bool {
        let v = value.lowercased()
        let host: Substring
        let portText: Substring?
        if v.hasPrefix("[") {
            guard let close = v.firstIndex(of: "]") else { return false }
            host = v[...close]
            let rest = v[v.index(after: close)...]
            if rest.isEmpty {
                portText = nil
            } else if rest.first == ":" {
                portText = rest.dropFirst()
            } else {
                return false
            }
        } else if let colon = v.firstIndex(of: ":") {
            host = v[..<colon]
            portText = v[v.index(after: colon)...]
        } else {
            host = v[...]
            portText = nil
        }
        guard ["localhost", "127.0.0.1", "[::1]"].contains(String(host)) else { return false }
        guard let portText else { return port == 80 }
        guard !portText.isEmpty,
              portText.allSatisfy({ $0.isASCII && $0.isNumber }),
              let p = UInt16(portText)
        else { return false }
        return p == port
    }

    static func isAuthorized(_ values: [String], token: String) -> Bool {
        guard values.count == 1 else { return false }
        let v = values[0]
        guard let space = v.firstIndex(where: { $0 == " " || $0 == "\t" }),
              v[..<space].lowercased() == "bearer"
        else { return false }
        let presented = trimSpaceAndTab(v[space...])
        return !presented.isEmpty && constantTimeEquals(presented, token)
    }

    static func isJSONMediaType(_ value: String) -> Bool {
        let mediaType = value.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)[0]
        return trimSpaceAndTab(mediaType).lowercased() == "application/json"
    }

    /// 32 bytes from the system CSPRNG, as 64 lowercase hex characters.
    static func makeToken() -> String {
        var rng = SystemRandomNumberGenerator()
        return (0..<32).map { _ in String(format: "%02x", UInt8.random(in: .min ... .max, using: &rng)) }.joined()
    }

    /// At least 16 characters from the RFC 6750 token set.
    static func isValidToken(_ s: String) -> Bool {
        s.count >= 16 && s.allSatisfy { c in
            guard let a = c.asciiValue else { return false }
            return (c.isLetter || c.isNumber) || "._~+/=-".utf8.contains(a)
        }
    }

    static func constantTimeEquals(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8)
        let y = Array(b.utf8)
        guard x.count == y.count else { return false }
        var diff: UInt8 = 0
        for i in x.indices { diff |= x[i] ^ y[i] }
        return diff == 0
    }
}
