import Foundation
import AVFoundation
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
    var videoDuration: Double? = nil
}

enum CompressionError: LocalizedError {
    case binaryNotFound(String)
    case processFailed(Int32, String)
    case outputMissing
    case pdfLoadFailed
    case pdfPageRenderFailed(Int)
    case videoExportFailed(String)
    case videoExportSessionUnavailable

    var errorDescription: String? {
        switch self {
        case .binaryNotFound(let n): return "Binary '\(n)' not found in app bundle."
        case .processFailed(let c, let e): return "Process exited \(c): \(e)"
        case .outputMissing: return "Output file was not created."
        case .pdfLoadFailed: return "Could not open the PDF file."
        case .pdfPageRenderFailed(let p): return "Could not render page \(p + 1)."
        case .videoExportFailed(let msg): return "Video export failed: \(msg)"
        case .videoExportSessionUnavailable: return "Could not create export session for this video."
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
        contentTypeHint: String = "auto",
        /// When Smart Quality is on and the caller already classified (e.g. Auto format), skip a second Vision pass.
        preclassifiedContent: ContentType? = nil
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

        // Step 2: classify for Smart Quality on the **original** URL (EXIF intact).
        // Off-actor so Vision/pixel work doesn't serialize on this actor.
        let detected: ContentType?
        if smartQuality, let preclassifiedContent {
            detected = preclassifiedContent
        } else if smartQuality {
            detected = await Task.detached { ContentClassifier.classify(source) }.value
        } else {
            switch contentTypeHint {
            case "photo": detected = .photo
            case "ui":    detected = .ui
            case "mixed": detected = .mixed
            default:      detected = nil
            }
        }

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
            // For UI/screenshot WebP, near-lossless preserves text edges that
            // even q=92 lossy softens. AVIF UI handles crispness via 4:4:4 + slower speed.
            let nl: Int? = (format == .webp && detected == .ui) ? 60 : nil
            try await compressAtQuality(source: workURL, quality: q,
                                        format: format, strip: stripMetadata, output: outputURL,
                                        content: detected, nearLossless: nl)
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

        // WebP / AVIF / BMP (etc.) must not round-trip through JPEG — use lossless TIFF.
        let ext: String
        if ["jpg", "jpeg", "png", "tiff"].contains(source.pathExtension.lowercased()) {
            ext = source.pathExtension
        } else {
            ext = "tiff"
        }
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
        let fm = FileManager.default

        // UI + WebP: binary-search `-near_lossless` (40…100) before lossy `-q`.
        // Higher values = closer to lossless = larger files; we maximize nl that still fits the cap.
        if format == .webp, content == .ui {
            var nlLo = 40, nlHi = 100
            var bestURL: URL?
            while nlLo <= nlHi {
                let mid = (nlLo + nlHi) / 2
                let tmp = fm.temporaryDirectory
                    .appendingPathComponent("dinky_nl\(mid)_\(UUID().uuidString)")
                    .appendingPathExtension(format.outputExtension)
                try await runCwebp(
                    source: source, quality: 100, strip: strip, output: tmp,
                    content: content, nearLossless: mid
                )
                if fileSize(tmp) <= targetBytes {
                    if let prev = bestURL { try? fm.removeItem(at: prev) }
                    bestURL = tmp
                    nlLo = mid + 1
                } else {
                    try? fm.removeItem(at: tmp)
                    nlHi = mid - 1
                }
            }
            if let best = bestURL {
                try fm.moveItem(at: best, to: output)
                return
            }
        }

        var lo = qualityFloor, hi = 92
        var bestURL: URL?

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
        content: ContentType?,
        nearLossless: Int? = nil
    ) async throws {
        switch format {
        case .webp: try await runCwebp(source: source, quality: quality, strip: strip, output: output, content: content, nearLossless: nearLossless)
        case .avif: try await runAvifenc(source: source, quality: quality, strip: strip, output: output, content: content)
        case .png:  try await runOxipng(source: source, strip: strip, output: output)
        }
    }

    private func runCwebp(source: URL, quality: Int, strip: Bool, output: URL, content: ContentType?, nearLossless: Int? = nil) async throws {
        let binary = try binaryURL("cwebp")
        let q = String(quality)
        var args: [String]
        if let nl = nearLossless {
            // Near-lossless: preprocesses pixel values for better compression
            // while keeping edges pixel-perfect. Best for UI / text screenshots.
            // -q here controls compression effort, not visual quality.
            args = ["-near_lossless", String(nl), "-m", "6", "-alpha_q", "100", "-exact", "-q", "100"]
        } else {
            // -preset must come first — it resets other flags.
            switch content {
            case .photo:  args = ["-preset", "photo",   "-m", "6", "-sharp_yuv", "-pass", "6", "-af", "-q", q]
            case .ui:     args = ["-preset", "text",    "-m", "6", "-sharp_yuv", "-alpha_q", "100", "-exact", "-q", q]
            case .mixed:  args = ["-preset", "picture", "-m", "6", "-sharp_yuv", "-q", q]
            case .none:   args = ["-preset", "picture", "-m", "6", "-q", q]
            }
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
        case .photo:  args = ["--speed", "4", "--yuv", "420", "--depth", "10", "--jobs", "all", "--qcolor", qColor, "--qalpha", qAlpha]
        // UI: 4:4:4 keeps color edges sharp (no chroma subsampling).
        // Speed 4 (slower than the default 6) noticeably improves text crispness.
        case .ui:     args = ["--speed", "4", "--yuv", "444", "--jobs", "all", "--qcolor", qColor, "--qalpha", qAlpha]
        case .mixed:  args = ["--speed", "5", "--yuv", "422", "--depth", "10", "--jobs", "all", "--qcolor", qColor, "--qalpha", qAlpha]
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

    // MARK: - PDF compression

    func compressPDF(
        source: URL,
        outputMode: PDFOutputMode,
        quality: PDFQuality,
        grayscale: Bool,
        stripMetadata: Bool,
        outputURL: URL
    ) async throws -> CompressionResult {
        let originalSize = fileSize(source)

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        switch outputMode {
        case .preserveStructure:
            try PDFCompressor.preserveStructure(source: source, stripMetadata: stripMetadata, outputURL: outputURL)
        case .flattenPages:
            try PDFCompressor.compressFlattened(
                source: source, quality: quality, grayscale: grayscale,
                stripMetadata: stripMetadata, outputURL: outputURL
            )
        }

        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw CompressionError.outputMissing
        }

        return CompressionResult(outputURL: outputURL,
                                 originalSize: originalSize,
                                 outputSize: fileSize(outputURL),
                                 detectedContentType: nil)
    }

    // MARK: - Video compression

    func compressVideo(
        source: URL,
        quality: VideoQuality,
        codec: VideoCodecFamily,
        removeAudio: Bool,
        outputURL: URL,
        progressHandler: (@Sendable (Float) -> Void)? = nil
    ) async throws -> CompressionResult {
        try await compressVideo(
            asset: VideoCompressor.makeURLAsset(url: source),
            source: source,
            quality: quality,
            codec: codec,
            removeAudio: removeAudio,
            outputURL: outputURL,
            progressHandler: progressHandler
        )
    }

    /// Reuses a pre-built ``AVURLAsset`` (e.g. shared with ``VideoSmartQuality``) to avoid reopening the file.
    func compressVideo(
        asset: AVURLAsset,
        source: URL,
        quality: VideoQuality,
        codec: VideoCodecFamily,
        removeAudio: Bool,
        outputURL: URL,
        progressHandler: (@Sendable (Float) -> Void)? = nil
    ) async throws -> CompressionResult {
        let originalSize = fileSize(source)

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let duration = try await VideoCompressor.compress(
            asset: asset,
            sourceForMetadata: source,
            quality: quality,
            codec: codec,
            removeAudio: removeAudio,
            outputURL: outputURL,
            progressHandler: progressHandler
        )

        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw CompressionError.outputMissing
        }

        return CompressionResult(outputURL: outputURL,
                                 originalSize: originalSize,
                                 outputSize: fileSize(outputURL),
                                 detectedContentType: nil,
                                 videoDuration: duration)
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
