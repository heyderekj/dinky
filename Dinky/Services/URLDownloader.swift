import DinkyCoreShared
import Foundation
import os.log

private let urlDownloadLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Dinky", category: "URLDownloader")

/// Direct `http(s)` media downloads for drag-and-drop / paste. No HTML scraping.
enum URLDownloader {

    static let maxBytes: Int64 = 500 * 1024 * 1024

    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = 5 * 60
        let ver = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1"
        cfg.httpAdditionalHeaders = [
            "User-Agent": "Dinky/\(ver) (+https://dinkyfiles.com)",
            "Accept": "image/*, video/*, application/pdf;q=0.9,*/*;q=0.1"
        ]
        cfg.waitsForConnectivity = false
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: cfg)
    }()

    /// Final path under `FileManager.default.temporaryDirectory/Dinky-Downloads/`.
    static func download(
        _ url: URL,
        onProgress: (@Sendable (Double, Int64?) -> Void)? = nil
    ) async throws -> URL {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw URLDownloaderError.invalidScheme
        }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"

        let (tempDownloadURL, response): (URL, URLResponse)
        do {
            (tempDownloadURL, response) = try await session.download(for: req)
        } catch let e as URLError where e.code == .notConnectedToInternet || e.code == .networkConnectionLost {
            throw URLDownloaderError.offline
        } catch let e as URLError where e.code == .timedOut {
            throw URLDownloaderError.timeout
        } catch {
            throw URLDownloaderError.network(error)
        }

        try Task.checkCancellation()

        guard let http = response as? HTTPURLResponse else {
            try? FileManager.default.removeItem(at: tempDownloadURL)
            throw URLDownloaderError.network(URLError(.badServerResponse))
        }

        switch http.statusCode {
        case 404: try? FileManager.default.removeItem(at: tempDownloadURL); throw URLDownloaderError.notFound
        case 403: try? FileManager.default.removeItem(at: tempDownloadURL); throw URLDownloaderError.forbidden
        case 200...299: break
        case 500...599: try? FileManager.default.removeItem(at: tempDownloadURL); throw URLDownloaderError.serverError(http.statusCode)
        default: try? FileManager.default.removeItem(at: tempDownloadURL); throw URLDownloaderError.serverError(http.statusCode)
        }

        let mime = http.mimeType?.lowercased()
        if let m = mime, m == "text/html" || m.hasPrefix("text/") {
            try? FileManager.default.removeItem(at: tempDownloadURL)
            throw URLDownloaderError.htmlPage
        }

        let expected = http.expectedContentLength > 0 ? http.expectedContentLength : nil
        if let e = expected, e > maxBytes {
            try? FileManager.default.removeItem(at: tempDownloadURL)
            throw URLDownloaderError.tooLarge
        }

        onProgress?(0, expected)

        let attrs = try? FileManager.default.attributesOfItem(atPath: tempDownloadURL.path)
        let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        if size > maxBytes {
            try? FileManager.default.removeItem(at: tempDownloadURL)
            throw URLDownloaderError.tooLarge
        }

        onProgress?(1, size)

        let destDir = downloadsScratchDirectory()
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

        let filename = resolvedFilename(for: url, response: http, tempPath: tempDownloadURL)
        let dest = uniquePath(in: destDir, filename: filename)

        if FileManager.default.fileExists(atPath: dest.path) {
            try? FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.moveItem(at: tempDownloadURL, to: dest)

        try Task.checkCancellation()

        guard MediaTypeDetector.detect(dest) != nil else {
            try? FileManager.default.removeItem(at: dest)
            throw URLDownloaderError.unsupportedType
        }

        urlDownloadLogger.debug("Downloaded host=\(url.host() ?? "?") bytes=\(size)")
        return dest
    }

    /// `…/tmp/Dinky-Downloads`
    static func downloadsScratchDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Dinky-Downloads", isDirectory: true)
    }

    /// Deletes files older than `maxAge` (default 24h) in the scratch directory.
    static func sweepOldDownloads(maxAge: TimeInterval = 24 * 60 * 60) {
        let dir = downloadsScratchDirectory()
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return }
        let now = Date()
        for name in names {
            let u = dir.appendingPathComponent(name)
            guard let d = try? u.resourceValues(forKeys: [.creationDateKey]), let created = d.creationDate else { continue }
            if now.timeIntervalSince(created) > maxAge {
                try? FileManager.default.removeItem(at: u)
            }
        }
    }

    // MARK: - Filename

    private static func resolvedFilename(for url: URL, response: HTTPURLResponse, tempPath: URL) -> String {
        if let cd = response.value(forHTTPHeaderField: "Content-Disposition"),
           let name = parseContentDispositionFilename(cd) {
            return sanitizeFilename(name)
        }
        let last = url.lastPathComponent
        if !last.isEmpty, last != "/", last.contains(".") {
            return sanitizeFilename(last)
        }
        let ext = MediaDownloadMIME.pathExtension(for: response.mimeType) ?? url.pathExtension.lowercased()
        let stem = url.host ?? "download"
        return sanitizeFilename("\(stem)-\(UUID().uuidString.prefix(8)).\(ext.isEmpty ? "bin" : ext)")
    }

    private static func parseContentDispositionFilename(_ value: String) -> String? {
        // attachment; filename="file.jpg"  or  filename=file.jpg
        // Avoid raw-string `"` ambiguity: use \x22 for quotes inside the pattern.
        if let r = try? NSRegularExpression(
            pattern: #"filename\*?=(?:UTF-8''|\x22)?([^\x22;]+)\x22?"#,
            options: .caseInsensitive
        ),
           let m = r.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
           m.numberOfRanges >= 2,
           let range = Range(m.range(at: 1), in: value) {
            return String(value[range]).removingPercentEncoding ?? String(value[range])
        }
        return nil
    }

    private static func sanitizeFilename(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "/", with: "-")
        t = t.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if t.count > 200 { t = String(t.prefix(200)) }
        return t.isEmpty ? "download.bin" : t
    }

    private static func uniquePath(in folder: URL, filename: String) -> URL {
        let base = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        var candidate = folder.appendingPathComponent(filename)
        var n = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            let stem = "\(base) (\(n))"
            candidate = folder.appendingPathComponent(stem).appendingPathExtension(ext)
            n += 1
        }
        return candidate
    }

}

enum URLDownloaderError: LocalizedError {
    case invalidScheme
    case offline
    case timeout
    case notFound
    case forbidden
    case serverError(Int)
    case htmlPage
    case unsupportedType
    case tooLarge
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .invalidScheme:
            return String(localized: "Only http or https links are supported.", comment: "Link download error.")
        case .offline:
            return String(localized: "You appear to be offline.", comment: "Link download error.")
        case .timeout:
            return String(localized: "Download timed out.", comment: "Link download error.")
        case .notFound:
            return String(localized: "That link couldn’t be found (404).", comment: "Link download error.")
        case .forbidden:
            return String(localized: "That link is restricted (403).", comment: "Link download error.")
        case .serverError(let c):
            return String(localized: "The server returned an error (\(c)).", comment: "Link download error; argument is an HTTP status code.")
        case .htmlPage:
            return String(localized: "That link points to a webpage, not an image, video, or PDF. Try copying the image address instead.", comment: "Link download error.")
        case .unsupportedType:
            return String(localized: "That file type isn’t supported by Dinky.", comment: "Link download error.")
        case .tooLarge:
            return String(localized: "That file is larger than 500 MB.", comment: "Link download error.")
        case .network(let e):
            return e.localizedDescription
        }
    }
}
