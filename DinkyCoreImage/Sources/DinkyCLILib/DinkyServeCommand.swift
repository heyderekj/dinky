import DinkyCoreImage
import DinkyCorePDF
import DinkyCoreShared
import DinkyCoreVideo
import Dispatch
import Foundation
import Network

struct DinkyServeCompressBody: Codable {
    var inputPaths: [String]
    var format: String?
    var outputDir: String?
    var maxWidth: Int?
    var maxSizeKB: Int?
    var quality: Int?
    var smartQuality: Bool?
    var stripMetadata: Bool?
    var contentHint: String?
    var parallel: Int?
}

struct DinkyServeVideoCompressBody: Codable {
    var inputPaths: [String]
    var outputDir: String?
    var quality: String?
    var codec: String?
    var removeAudio: Bool?
    var maxHeight: Int?
    /// When false, disables FPS cap. When omitted, FPS cap follows `maxFPS` / defaults.
    var fpsCapEnabled: Bool?
    /// When set, enables cap with this frame rate (60 / 30 / 24 / 15); normalized if needed.
    var maxFPS: Int?
    var smartQuality: Bool?
}

struct DinkyServePdfCompressBody: Codable {
    var inputPaths: [String]
    var outputDir: String?
    var mode: String?
    var quality: String?
    var grayscale: Bool?
    var stripMetadata: Bool?
    var resolutionDownsample: Bool?
    var targetKB: Int?
    var preserveExperimental: String?
    var smartQuality: Bool?
    var autoGrayscaleMono: Bool?
}

struct DinkyServeOptions: Equatable, Sendable {
    enum TokenSource: Equatable, Sendable { case generated, environment, flag }
    var port: UInt16 = 17381
    /// Pinned token from `--token` / `DINKY_SERVE_TOKEN`; `nil` means generate one at launch.
    var token: String?
    var tokenSource: TokenSource = .generated
}

public enum DinkyServeCommand {
    static let usage = "dinky serve [--port <n>] [--token <value>]   (or set DINKY_SERVE_TOKEN)"

    public static func runBlocking(args: [String]) -> Never {
        let options: DinkyServeOptions
        do {
            options = try parseArgs(args)
        } catch let e as DinkyCLIParseError {
            die("dinky: \(e.message)")
        } catch {
            die("dinky: \(error.localizedDescription)")
        }
        let port = options.port
        let token = options.token ?? DinkyServeRequestGuard.makeToken()
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { die("dinky: invalid --port (use 1-65535)") }

        let queue = DispatchQueue(label: "dinky.serve", qos: .userInitiated, attributes: .concurrent)
        let events = DispatchQueue(label: "dinky.serve.listen")
        let v4: NWListener
        do {
            v4 = try NWListener(using: loopbackParameters(.ipv4(.loopback), port: nwPort))
        } catch {
            die("dinky serve: could not listen on 127.0.0.1:\(port) (\(error))")
        }
        let v6 = try? NWListener(using: loopbackParameters(.ipv6(.loopback), port: nwPort))
        for listener in [v4, v6].compactMap({ $0 }) {
            listener.newConnectionHandler = { receiveHTTP(connection: $0, queue: queue, port: port, token: token) }
        }

        let v4Ready = DispatchSemaphore(value: 0)
        v4.stateUpdateHandler = { state in
            switch state {
            case .ready: v4Ready.signal()
            case .failed(let e), .waiting(let e): die(listenFailure(e, host: "127.0.0.1", port: port))
            default: break
            }
        }
        let v6Settled = DispatchSemaphore(value: 0)
        if let v6 {
            v6.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    v6Settled.signal()
                case .failed(let e), .waiting(let e):
                    // Someone else holding [::1]:port would receive tokens from clients that try `localhost` over IPv6 first.
                    if case .posix(.EADDRINUSE) = e { die(listenFailure(e, host: "[::1]", port: port)) }
                    warn("dinky serve: warning: [::1]:\(port) unavailable (\(e)); serving on 127.0.0.1 only.")
                    v6.cancel()
                    v6Settled.signal()
                default:
                    break
                }
            }
            v6.start(queue: events)
        } else {
            warn("dinky serve: warning: IPv6 loopback unavailable; serving on 127.0.0.1 only.")
        }
        v4.start(queue: events)
        if v4Ready.wait(timeout: .now() + 5) == .timedOut {
            die("dinky serve: timed out opening 127.0.0.1:\(port)")
        }
        if let v6, v6Settled.wait(timeout: .now() + 2) == .timedOut { v6.cancel() }
        let ipv6Up = v6?.state == .ready
        FileHandle.standardError.write(Data(banner(port: port, ipv6: ipv6Up, token: token, source: options.tokenSource).utf8))
        withExtendedLifetime((v4, v6)) { dispatchMain() }
    }

    static func parseArgs(
        _ args: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> DinkyServeOptions {
        var o = DinkyServeOptions()
        var flagToken: String?
        var i = 0
        let n = args.count
        while i < n {
            let a = args[i]
            switch a {
            case "-h", "--help":
                throw DinkyCLIParseError(message: "usage: \(usage)")
            case "--port":
                i += 1
                guard i < n, let p = UInt16(args[i]), p > 0 else {
                    throw DinkyCLIParseError(message: "invalid --port (use 1-65535)")
                }
                o.port = p
            case "--token":
                i += 1
                guard i < n else { throw DinkyCLIParseError(message: "missing value for --token") }
                flagToken = args[i]
            default:
                throw DinkyCLIParseError(message: "unknown option: \(a)")
            }
            i += 1
        }
        let tokenRule = "at least 16 characters from A-Z a-z 0-9 . _ ~ + / = -"
        if let t = flagToken {
            guard DinkyServeRequestGuard.isValidToken(t) else {
                throw DinkyCLIParseError(message: "--token must be \(tokenRule)")
            }
            o.token = t
            o.tokenSource = .flag
        } else if let t = environment[DinkyServeRequestGuard.tokenEnvironmentKey], !t.isEmpty {
            guard DinkyServeRequestGuard.isValidToken(t) else {
                throw DinkyCLIParseError(message: "\(DinkyServeRequestGuard.tokenEnvironmentKey) must be \(tokenRule)")
            }
            o.token = t
            o.tokenSource = .environment
        }
        return o
    }

    /// Startup banner (stderr). A pinned token is never echoed.
    static func banner(port: UInt16, ipv6: Bool, token: String, source: DinkyServeOptions.TokenSource) -> String {
        let urls = ipv6 ? "http://127.0.0.1:\(port) and http://[::1]:\(port)" : "http://127.0.0.1:\(port)"
        let bearer: String
        switch source {
        case .generated: bearer = "\(token)  (new each launch; set DINKY_SERVE_TOKEN to keep one)"
        case .environment: bearer = "<your DINKY_SERVE_TOKEN>"
        case .flag: bearer = "<your --token>"
        }
        return """
        dinky serve: listening on \(urls) (this Mac only). Ctrl-C to stop.
        dinky serve: POST /v1/compress, /v1/video/compress, /v1/pdf/compress (Content-Type: application/json); GET /v1/health
        dinky serve: Authorization: Bearer \(bearer)

        """
    }

    /// Binds one loopback address only; the port must live in the endpoint (`NWListener(using:on:)` rejects it).
    private static func loopbackParameters(_ host: NWEndpoint.Host, port: NWEndpoint.Port) -> NWParameters {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredInterfaceType = .loopback
        parameters.requiredLocalEndpoint = .hostPort(host: host, port: port)
        return parameters
    }

    private static func listenFailure(_ error: NWError, host: String, port: UInt16) -> String {
        if case .posix(.EADDRINUSE) = error {
            return "dinky serve: port \(port) is already in use on \(host) (another dinky serve?). Stop it or use --port <n>."
        }
        return "dinky serve: could not listen on \(host):\(port) (\(error))"
    }

    private static func warn(_ message: String) {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
    }

    private static func die(_ message: String) -> Never {
        warn(message)
        exit(1)
    }

    private static func receiveHTTP(connection: NWConnection, queue: DispatchQueue, port: UInt16, token: String) {
        connection.start(queue: queue)
        let acc = RecvBuffer()
        @Sendable
        func recv() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 2_000_000) { data, _, isComplete, error in
                if let d = data, !d.isEmpty { acc.append(d) }
                if let error {
                    _ = error
                    connection.cancel()
                    return
                }
                if isComplete, acc.isEmpty {
                    connection.cancel()
                    return
                }
                if !acc.isEmpty, let s = acc.utf8String(), s.contains("\r\n\r\n") {
                    handleRawHTTP(s, connection: connection, queue: queue, port: port, token: token)
                    return
                }
                if isComplete, !acc.isEmpty, let s = acc.utf8String() {
                    handleRawHTTP(s, connection: connection, queue: queue, port: port, token: token)
                    return
                }
                if !isComplete { recv() }
            }
        }
        recv()
    }

    private static func handleRawHTTP(_ raw: String, connection: NWConnection, queue: DispatchQueue, port: UInt16, token: String) {
        let headText: Substring
        let body: String
        if let blank = raw.range(of: "\r\n\r\n") {
            headText = raw[..<blank.lowerBound]
            body = String(raw[blank.upperBound...])
        } else {
            headText = raw[...]
            body = ""
        }
        guard let head = DinkyServeRequestHead.parse(String(headText)) else {
            send(connection: connection, status: 400, body: "{\"error\":\"bad request\"}")
            return
        }
        if let rejection = DinkyServeRequestGuard.check(head, port: port, token: token) {
            send(connection: connection, status: rejection.status, body: rejection.body, headers: rejection.headers)
            return
        }
        if head.isHealthCheck {
            let b = "{\"ok\":true,\"schema\":\"\(dinkyImageServeInfoSchema)\"}\n"
            send(connection: connection, status: 200, body: b)
            return
        }
        if head.method == "POST", head.target == "/v1/compress" {
            Task {
                await handleCompressPOST(body: body, connection: connection, queue: queue)
            }
            return
        }
        if head.method == "POST", head.target == "/v1/video/compress" {
            Task {
                await handleVideoCompressPOST(body: body, connection: connection, queue: queue)
            }
            return
        }
        if head.method == "POST", head.target == "/v1/pdf/compress" {
            Task {
                await handlePdfCompressPOST(body: body, connection: connection, queue: queue)
            }
            return
        }
        send(connection: connection, status: 404, body: "{\"error\":\"not found\"}")
    }

    private static func handleCompressPOST(body: String, connection: NWConnection, queue: DispatchQueue) async {
        guard let d = body.data(using: .utf8), let msg = try? JSONDecoder().decode(DinkyServeCompressBody.self, from: d) else {
            await sendOnQueue(queue, connection, status: 400, body: "{\"error\":\"invalid JSON\"}")
            return
        }
        if msg.inputPaths.isEmpty {
            await sendOnQueue(queue, connection, status: 400, body: "{\"error\":\"inputPaths required\"}")
            return
        }
        var o = DinkyCompressOptions()
        o.format = msg.format?.lowercased() ?? "auto"
        o.json = true
        if let dir = msg.outputDir { o.outputDir = URL(fileURLWithPath: dir, isDirectory: true) }
        o.maxWidth = msg.maxWidth
        o.maxFileSizeKB = msg.maxSizeKB
        o.quality = msg.quality
        if let sq = msg.smartQuality { o.smartQuality = sq }
        if o.quality != nil { o.smartQuality = false }
        if let m = msg.stripMetadata { o.stripMetadata = m }
        o.contentTypeHint = msg.contentHint ?? "auto"
        if let p = msg.parallel { o.parallelLimit = max(1, p) }
        let (code, results) = await DinkyCompressCommand.runWithOptions(o, paths: msg.inputPaths)
        let payload = DinkyImageCompressResponse(
            schema: dinkyImageCompressResultSchema,
            success: code == 0,
            results: results
        )
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        if let out = try? enc.encode(payload), let s = String(data: out, encoding: .utf8) {
            let status: Int = code == 0 ? 200 : 422
            await sendOnQueue(queue, connection, status: status, body: s)
        } else {
            await sendOnQueue(queue, connection, status: 500, body: "{\"error\":\"encode failed\"}")
        }
    }

    private static func handleVideoCompressPOST(body: String, connection: NWConnection, queue: DispatchQueue) async {
        guard let d = body.data(using: .utf8), let msg = try? JSONDecoder().decode(DinkyServeVideoCompressBody.self, from: d) else {
            await sendOnQueue(queue, connection, status: 400, body: "{\"error\":\"invalid JSON\"}")
            return
        }
        if msg.inputPaths.isEmpty {
            await sendOnQueue(queue, connection, status: 400, body: "{\"error\":\"inputPaths required\"}")
            return
        }
        var o = DinkyVideoCompressOptions()
        o.json = true
        if let dir = msg.outputDir { o.outputDir = URL(fileURLWithPath: dir, isDirectory: true) }
        if let q = msg.quality {
            let t = q.lowercased()
            if t == "low" { o.quality = .medium }
            else if t == "lossless" { o.quality = .high }
            else { o.quality = VideoQuality(rawValue: t) ?? .medium }
        }
        if let c = msg.codec?.lowercased(), let codec = VideoCodecFamily(rawValue: c) {
            o.codec = codec
        }
        if let r = msg.removeAudio { o.removeAudio = r }
        o.maxResolutionLines = msg.maxHeight
        if let en = msg.fpsCapEnabled {
            o.fpsCapEnabled = en
            if en, let mf = msg.maxFPS {
                o.fpsCap = VideoFPSCapPreset.normalizeStored(mf)
            }
        } else if let mf = msg.maxFPS {
            o.fpsCapEnabled = true
            o.fpsCap = VideoFPSCapPreset.normalizeStored(mf)
        }
        if let sq = msg.smartQuality {
            o.smartQuality = sq
        } else if msg.quality != nil {
            o.smartQuality = false
        }
        let (code, results) = await DinkyVideoCompressCommand.runWithOptions(o, paths: msg.inputPaths, preset: nil)
        let payload = DinkyVideoCompressResponse(
            schema: dinkyVideoCompressResultSchema,
            success: code == 0,
            results: results
        )
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        if let out = try? enc.encode(payload), let s = String(data: out, encoding: .utf8) {
            let status: Int = code == 0 ? 200 : 422
            await sendOnQueue(queue, connection, status: status, body: s)
        } else {
            await sendOnQueue(queue, connection, status: 500, body: "{\"error\":\"encode failed\"}")
        }
    }

    private static func handlePdfCompressPOST(body: String, connection: NWConnection, queue: DispatchQueue) async {
        guard let d = body.data(using: .utf8), let msg = try? JSONDecoder().decode(DinkyServePdfCompressBody.self, from: d) else {
            await sendOnQueue(queue, connection, status: 400, body: "{\"error\":\"invalid JSON\"}")
            return
        }
        if msg.inputPaths.isEmpty {
            await sendOnQueue(queue, connection, status: 400, body: "{\"error\":\"inputPaths required\"}")
            return
        }
        guard let bin = DinkyEncoderPath.resolveBinDirectory() else {
            await sendOnQueue(queue, connection, status: 503, body: "{\"error\":\"DINKY_BIN encoders not found\"}")
            return
        }
        let qpdf = DinkyEncoderPath.qpdfExecutable(inBinDirectory: bin)
        var o = DinkyPdfCompressOptions()
        o.json = true
        if let dir = msg.outputDir { o.outputDir = URL(fileURLWithPath: dir, isDirectory: true) }
        if let m = msg.mode?.lowercased() {
            switch m {
            case "preserve": o.outputMode = .preserveStructure
            case "flatten": o.outputMode = .flattenPages
            default: break
            }
        }
        if let q = msg.quality?.lowercased(), let pq = PDFQuality(rawValue: q) {
            o.quality = pq
        }
        if let g = msg.grayscale { o.grayscale = g }
        if let s = msg.stripMetadata { o.stripMetadata = s }
        if let r = msg.resolutionDownsample { o.resolutionDownsampling = r }
        o.targetKB = msg.targetKB
        if let e = msg.preserveExperimental {
            let v = e.lowercased()
            let raw: String
            switch v {
            case "none", "off": raw = PDFPreserveExperimentalMode.none.rawValue
            case "stripstructure", "strip": raw = PDFPreserveExperimentalMode.stripNonEssentialStructure.rawValue
            case "strongerimages", "stronger": raw = PDFPreserveExperimentalMode.strongerImageRecompression.rawValue
            case "maximum", "max": raw = PDFPreserveExperimentalMode.maximum.rawValue
            default: raw = v
            }
            if let mode = PDFPreserveExperimentalMode(rawValue: raw) {
                o.preserveExperimental = mode
            }
        }
        if let sq = msg.smartQuality { o.smartQuality = sq }
        if let ag = msg.autoGrayscaleMono { o.autoGrayscaleMonoScans = ag }
        let (code, results) = await DinkyPdfCompressCommand.runWithOptions(o, paths: msg.inputPaths, preset: nil, qpdfBinary: qpdf)
        let payload = DinkyPdfCompressResponse(
            schema: dinkyPdfCompressResultSchema,
            success: code == 0,
            results: results
        )
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        if let out = try? enc.encode(payload), let s = String(data: out, encoding: .utf8) {
            let status: Int = code == 0 ? 200 : 422
            await sendOnQueue(queue, connection, status: status, body: s)
        } else {
            await sendOnQueue(queue, connection, status: 500, body: "{\"error\":\"encode failed\"}")
        }
    }

    private static func sendOnQueue(_ q: DispatchQueue, _ c: NWConnection, status: Int, body: String) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            q.async {
                send(connection: c, status: status, body: body)
                cont.resume()
            }
        }
    }

    private static func send(connection: NWConnection, status: Int, body: String, headers: [String: String] = [:]) {
        let extra = headers.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)\r\n" }.joined()
        let r = "HTTP/1.1 \(status) \(reasonPhrase(status))\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\n\(extra)Connection: close\r\n\r\n\(body)"
        let data = Data(r.utf8)
        connection.send(content: data, isComplete: true, completion: .contentProcessed { _ in connection.cancel() })
    }

    private static func reasonPhrase(_ status: Int) -> String {
        switch status {
        case 200: "OK"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 403: "Forbidden"
        case 404: "Not Found"
        case 415: "Unsupported Media Type"
        case 422: "Unprocessable Content"
        case 500: "Internal Server Error"
        case 503: "Service Unavailable"
        default: "Error"
        }
    }
}

/// Thread-safe buffer for a single `NWConnection` receive stream.
private final class RecvBuffer: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()

    var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return data.isEmpty
    }

    func append(_ more: Data) {
        lock.lock()
        defer { lock.unlock() }
        data.append(more)
    }

    func utf8String() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return String(data: data, encoding: .utf8)
    }
}
