import Foundation
import CoreGraphics
import ImageIO

struct CompressionGoals {
    var maxWidth: Int?       // nil = no limit (pixels)
    var maxFileSizeKB: Int?  // nil = no limit
}

struct CompressionResult {
    let outputURL: URL
    let originalSize: Int64
    let outputSize: Int64
    let detectedContentType: ContentType?   // nil when Smart Quality is off
}

enum CompressionError: LocalizedError {
    case binaryNotFound(String)
    case processFailed(Int32, String)
    case outputMissing

    var errorDescription: String? {
        switch self {
        case .binaryNotFound(let n): return "Binary '\(n)' not found in app bundle."
        case .processFailed(let c, let e): return "Process exited \(c): \(e)"
        case .outputMissing: return "Output file was not created."
        }
    }
}

// Default quality per format (used when Smart Quality is off, or as a fallback).
private let defaultQuality: [CompressionFormat: Int] = [
    .webp: 82,
    .avif: 75,
]

// Smart Quality: per-content-type quality for each format.
// UI/screenshots get higher quality to keep text crisp. Photos stay at our
// tuned defaults. Mixed lands in between.
private let qualityByContent: [ContentType: [CompressionFormat: Int]] = [
    .photo: [.webp: 82, .avif: 75],
    .ui:    [.webp: 92, .avif: 88],
    .mixed: [.webp: 87, .avif: 82],
]

// Floor for the binary-search target-size mode. UI screenshots shouldn't
// ever drop below this quality floor even when chasing a file size target.
private let targetSizeFloor: [ContentType: Int] = [
    .photo: 10,
    .ui:    50,
    .mixed: 25,
]

actor CompressionService {

    static let shared = CompressionService()

    private let binDir: URL = {
        guard let url = Bundle.main.resourceURL else {
            fatalError("Bundle.main.resourceURL is nil — app bundle is malformed")
        }
        return url
    }()

    // MARK: - Public

    func compress(
        source: URL,
        format: CompressionFormat,
        goals: CompressionGoals,
        stripMetadata: Bool,
        outputURL: URL,
        moveToTrash: Bool = false,
        smartQuality: Bool = false,
        contentTypeHint: String = "auto"
    ) async throws -> CompressionResult {
        let originalSize = fileSize(source)

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // Step 1: maybe resize
        let workURL = try await maybeResize(source: source, maxWidth: goals.maxWidth)
        let isTempWork = workURL != source
        defer { if isTempWork { try? FileManager.default.removeItem(at: workURL) } }

        // Step 2: classify for Smart Quality. Always classify the original —
        // resizing doesn't meaningfully change content type and keeps EXIF intact.
        // smartQuality ON = auto-detect per image. OFF = use explicit hint, or nil (no adjustment).
        let detected: ContentType? = {
            if smartQuality { return ContentClassifier.classify(source) }
            switch contentTypeHint {
            case "photo": return .photo
            case "ui":    return .ui
            case "mixed": return .mixed
            default:      return nil
            }
        }()

        // Step 3: compress — lossless formats skip quality targeting
        if format == .png {
            try await compressAtQuality(source: workURL, quality: 0,
                                        format: format, strip: stripMetadata, output: outputURL,
                                        content: detected)
        } else if let targetKB = goals.maxFileSizeKB {
            let floor = detected.flatMap { targetSizeFloor[$0] } ?? 10
            try await compressToTargetSize(
                source: workURL, targetBytes: Int64(targetKB) * 1024,
                format: format, strip: stripMetadata, output: outputURL,
                qualityFloor: floor, content: detected
            )
        } else {
            let q = quality(for: format, content: detected)
            try await compressAtQuality(source: workURL, quality: q,
                                        format: format, strip: stripMetadata, output: outputURL,
                                        content: detected)
        }

        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw CompressionError.outputMissing
        }

        if moveToTrash {
            try? FileManager.default.trashItem(at: source, resultingItemURL: nil)
        }

        return CompressionResult(outputURL: outputURL,
                                 originalSize: originalSize,
                                 outputSize: fileSize(outputURL),
                                 detectedContentType: detected)
    }

    /// Resolve quality based on Smart Quality classification (if available).
    private func quality(for format: CompressionFormat, content: ContentType?) -> Int {
        if let content, let q = qualityByContent[content]?[format] { return q }
        return defaultQuality[format] ?? 82
    }

    // MARK: - Resize (sips, built-in to macOS)

    private func maybeResize(source: URL, maxWidth: Int?) async throws -> URL {
        guard let maxWidth else { return source }

        // Check current dimensions
        guard let size = imageSize(source), Int(size.width) > maxWidth else {
            return source  // already within limit, skip resize
        }

        let ext    = ["jpg", "jpeg", "png", "tiff"].contains(source.pathExtension.lowercased())
                     ? source.pathExtension : "jpg"
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dinky_resize_\(UUID().uuidString)")
            .appendingPathExtension(ext)

        try await run(URL(fileURLWithPath: "/usr/bin/sips"),
                      args: ["--resampleWidth", String(maxWidth), source.path, "--out", tmpURL.path])
        return tmpURL
    }

    // MARK: - Quality binary search for file-size target

    private func compressToTargetSize(
        source: URL, targetBytes: Int64,
        format: CompressionFormat, strip: Bool, output: URL,
        qualityFloor: Int = 10,
        content: ContentType?
    ) async throws {
        var lo = qualityFloor, hi = 92
        var bestURL: URL?
        let fm = FileManager.default

        while lo <= hi {
            let mid = (lo + hi) / 2
            let tmp = fm.temporaryDirectory
                .appendingPathComponent("dinky_q\(mid)_\(UUID().uuidString)")
                .appendingPathExtension(format.outputExtension)

            try await compressAtQuality(source: source, quality: mid, format: format, strip: strip, output: tmp, content: content)

            if fileSize(tmp) <= targetBytes {
                if let prev = bestURL { try? fm.removeItem(at: prev) }
                bestURL = tmp
                lo = mid + 1     // fits — try higher quality
            } else {
                try? fm.removeItem(at: tmp)
                hi = mid - 1     // too big — lower quality
            }
        }

        if let best = bestURL {
            try fm.moveItem(at: best, to: output)
        } else {
            // Nothing met the target — use floor quality and let caller decide
            try await compressAtQuality(source: source, quality: qualityFloor,
                                        format: format, strip: strip, output: output,
                                        content: content)
        }
    }

    // MARK: - Format runners

    private func compressAtQuality(
        source: URL, quality: Int,
        format: CompressionFormat, strip: Bool, output: URL,
        content: ContentType?
    ) async throws {
        switch format {
        case .webp: try await runCwebp(source: source, quality: quality, strip: strip, output: output, content: content)
        case .avif: try await runAvifenc(source: source, quality: quality, strip: strip, output: output, content: content)
        case .png:  try await runOxipng(source: source, strip: strip, output: output)
        }
    }

    private func runCwebp(source: URL, quality: Int, strip: Bool, output: URL, content: ContentType?) async throws {
        let binary = try binaryURL("cwebp")
        let q = String(quality)
        // -preset must come first — it resets other flags.
        var args: [String]
        switch content {
        case .photo:  args = ["-preset", "photo",   "-m", "6", "-sharp_yuv", "-pass", "6", "-af", "-q", q]
        case .ui:     args = ["-preset", "text",    "-m", "6", "-alpha_q", "100", "-exact", "-q", q]
        case .mixed:  args = ["-preset", "picture", "-m", "6", "-sharp_yuv", "-q", q]
        case .none:   args = ["-preset", "picture", "-m", "6", "-q", q]
        }
        if strip { args += ["-metadata", "none"] }
        args += [source.path, "-o", output.path]
        try await run(binary, args: args)
    }

    private func runAvifenc(source: URL, quality: Int, strip: Bool, output: URL, content: ContentType?) async throws {
        let binary = try binaryURL("avifenc")
        let qColor = String(quality)
        let qAlpha = String(min(quality + 10, 100))
        var args: [String]
        switch content {
        case .photo:  args = ["--speed", "4", "--yuv", "420", "--jobs", "all", "--qcolor", qColor, "--qalpha", qAlpha]
        case .ui:     args = ["--speed", "6", "--yuv", "444", "--jobs", "all", "--qcolor", qColor, "--qalpha", qAlpha]
        case .mixed:  args = ["--speed", "5", "--yuv", "422", "--jobs", "all", "--qcolor", qColor, "--qalpha", qAlpha]
        case .none:   args = ["--speed", "5", "--yuv", "420", "--jobs", "all", "--qcolor", qColor, "--qalpha", qAlpha]
        }
        if strip { args += ["--ignore-exif", "--ignore-xmp"] }
        args += [source.path, output.path]
        try await run(binary, args: args)
    }

    private func runOxipng(source: URL, strip: Bool, output: URL) async throws {
        let binary = try binaryURL("oxipng")
        // Copy source to output first — oxipng optimizes in-place with --out
        try FileManager.default.copyItem(at: source, to: output)
        var args = ["--opt", "max"]
        if strip { args += ["--strip", "all"] }
        args += ["--out", output.path, output.path]
        try await run(binary, args: args)
    }

    // MARK: - Process runner

    private func run(_ binary: URL, args: [String]) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = binary
            process.arguments     = args

            // Homebrew binaries use @rpath dylibs that live in /opt/homebrew/lib.
            // Inject that path so dyld can find them when running inside the app bundle.
            var env = ProcessInfo.processInfo.environment
            let existing = env["DYLD_LIBRARY_PATH"].flatMap { $0.isEmpty ? nil : $0 }
            env["DYLD_LIBRARY_PATH"] = ["/opt/homebrew/lib", existing].compactMap { $0 }.joined(separator: ":")
            process.environment = env

            let errPipe = Pipe()
            process.standardError  = errPipe
            process.standardOutput = Pipe()
            process.terminationHandler = { p in
                let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(),
                                    encoding: .utf8) ?? ""
                if p.terminationStatus == 0 {
                    cont.resume()
                } else {
                    cont.resume(throwing: CompressionError.processFailed(p.terminationStatus, stderr))
                }
            }
            do    { try process.run() }
            catch { cont.resume(throwing: error) }
        }
    }

    // MARK: - Helpers

    private func binaryURL(_ name: String) throws -> URL {
        let url = binDir.appendingPathComponent(name)
        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            throw CompressionError.binaryNotFound(name)
        }
        return url
    }

    private func fileSize(_ url: URL) -> Int64 {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { Int64($0) } ?? 0
    }

    private func imageSize(_ url: URL) -> CGSize? {
        guard let src   = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any],
              let w     = props[kCGImagePropertyPixelWidth  as String] as? Int,
              let h     = props[kCGImagePropertyPixelHeight as String] as? Int
        else { return nil }
        return CGSize(width: w, height: h)
    }
}
