import Foundation
import AVFoundation
import CoreGraphics
import ImageIO
import PDFKit
import UniformTypeIdentifiers

struct CompressionGoals {
    var maxWidth: Int?       // nil = no limit (pixels)
    var maxFileSizeKB: Int?  // nil = no limit
}

struct CompressionResult {
    let outputURL: URL
    let originalSize: Int64
    let outputSize: Int64
    /// Where the original file was moved (Trash or backup) after compress, when applicable. Used for undo.
    var originalRecoveryURL: URL? = nil
    let detectedContentType: ContentType?   // nil when Smart Quality is off
    var videoDuration: Double? = nil
    /// Detected video content (screen recording / camera / generic). `nil` for non-video.
    var videoContentType: VideoContentType? = nil
    /// True when the source carried HDR (HLG / PQ / Dolby Vision) — preserved on export.
    var videoIsHDR: Bool = false
    /// Codec the export actually used. For HDR sources this may differ from the user's choice
    /// because we force HEVC to keep HDR metadata intact.
    var videoEffectiveCodec: VideoCodecFamily? = nil
    /// True when the source had multiple frames/pages (e.g. GIF, multi-page TIFF) and only the first was encoded.
    var usedFirstFrameOnly: Bool = false
}

enum CompressionError: LocalizedError {
    case binaryNotFound(String)
    case processFailed(Int32, String)
    case outputMissing
    case pdfLoadFailed
    case pdfPageRenderFailed(Int)
    case videoExportFailed(String)
    case videoExportSessionUnavailable
    case heicTranscodeFailed
    case heicEncodeFailed
    case imageResizeFailed
    case imageReadFailed
    case imageWriteFailed

    var errorDescription: String? {
        switch self {
        case .binaryNotFound(let n): return "Binary '\(n)' not found in app bundle."
        case .processFailed(let c, let e): return "Process exited \(c): \(e)"
        case .outputMissing: return "Output file was not created."
        case .pdfLoadFailed: return "Could not open the PDF file."
        case .pdfPageRenderFailed(let p): return "Could not render page \(p + 1)."
        case .videoExportFailed(let msg): return "Video export failed: \(msg)"
        case .videoExportSessionUnavailable: return "Could not create export session for this video."
        case .heicTranscodeFailed: return "Could not read or convert this HEIC/HEIF image."
        case .heicEncodeFailed:
            return String(localized: "Could not encode this image as HEIC.", comment: "Error when HEIC export fails.")
        case .imageResizeFailed: return "Could not resize this image for the width limit."
        case .imageReadFailed:
            return String(localized: "Could not read image data from this file.", comment: "Error when ImageIO fails to read source.")
        case .imageWriteFailed:
            return String(localized: "Could not write the compressed image file.", comment: "Error when ImageIO fails to finalize output.")
        }
    }
}

// Default quality per format (used when Smart Quality is off, or as a fallback).
private let defaultQuality: [CompressionFormat: Int] = [
    .webp: 82,
    .avif: 75,
    .heic: 78,
]

// Smart Quality: per-content-type quality for each format.
// Graphics (UI, screenshots, illustrations, logos) get higher quality to keep
// edges crisp. Photos stay at our tuned defaults. Mixed lands in between.
private let qualityByContent: [ContentType: [CompressionFormat: Int]] = [
    .photo:   [.webp: 82, .avif: 75, .heic: 78],
    .graphic: [.webp: 92, .avif: 88, .heic: 88],
    .mixed:   [.webp: 87, .avif: 82, .heic: 83],
]

// Floor for the binary-search target-size mode. Graphics shouldn't
// ever drop below this quality floor even when chasing a file size target.
private let targetSizeFloor: [ContentType: Int] = [
    .photo:   10,
    .graphic: 50,
    .mixed:   25,
]

// MARK: - Heavy work off the `CompressionService` actor

private let orientedFullImageDecodeOptions: [CFString: Any] = [
    kCGImageSourceCreateThumbnailFromImageAlways: true,
    kCGImageSourceCreateThumbnailWithTransform: true,
    kCGImageSourceThumbnailMaxPixelSize: 32_768,
    kCGImageSourceShouldCacheImmediately: true,
]

/// Full-resolution decode with EXIF orientation applied (matches Smart Quality thumbnails).
private func cgImageDecodedOrientedFullSize(url: URL) throws -> CGImage {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          CGImageSourceGetCount(src) > 0 else {
        throw CompressionError.imageResizeFailed
    }
    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(src, 0, orientedFullImageDecodeOptions as CFDictionary) else {
        throw CompressionError.imageResizeFailed
    }
    return cgImage
}

private func orientedPixelSize(url: URL) -> CGSize? {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any]
    else { return nil }

    let w: Int
    if let i = props[kCGImagePropertyPixelWidth as String] as? Int { w = i }
    else if let n = props[kCGImagePropertyPixelWidth as String] as? NSNumber { w = n.intValue }
    else { return nil }

    let h: Int
    if let i = props[kCGImagePropertyPixelHeight as String] as? Int { h = i }
    else if let n = props[kCGImagePropertyPixelHeight as String] as? NSNumber { h = n.intValue }
    else { return nil }

    let orientVal: UInt32
    if let u = props[kCGImagePropertyOrientation as String] as? UInt32 { orientVal = u }
    else if let i = props[kCGImagePropertyOrientation as String] as? Int, i >= 0 { orientVal = UInt32(i) }
    else if let n = props[kCGImagePropertyOrientation as String] as? NSNumber { orientVal = n.uint32Value }
    else { orientVal = 1 }

    // Display width/height: swap for left/right EXIF orientations (5…8).
    let swapWH = (5...8).contains(Int(orientVal))
    let dw = swapWH ? h : w
    let dh = swapWH ? w : h
    return CGSize(width: dw, height: dh)
}

private func imageSourceHasMultipleFrames(url: URL) -> Bool {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return false }
    return CGImageSourceGetCount(src) > 1
}

/// HEIC/HEIF → PNG when bundled CLI encoders need a readable path; skip when output is HEIC (ImageIO reads HEIC directly).
private func encoderInputURLForImageCompression(source: URL, outputFormat: CompressionFormat) throws -> URL {
    let ext = source.pathExtension.lowercased()
    if outputFormat == .heic, ext == "heic" || ext == "heif" {
        return source
    }
    return try heicTranscodeToPNGIfNeeded(source: source)
}

/// Lossless pixel decode to PNG so `cwebp` / `avifenc` / `oxipng` can read the file.
private func heicTranscodeToPNGIfNeeded(source: URL) throws -> URL {
    let ext = source.pathExtension.lowercased()
    guard ext == "heic" || ext == "heif" else { return source }

    let cgImage: CGImage
    do {
        cgImage = try cgImageDecodedOrientedFullSize(url: source)
    } catch {
        throw CompressionError.heicTranscodeFailed
    }

    let tmpURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("dinky_heic_\(UUID().uuidString)")
        .appendingPathExtension("png")

    guard let dest = CGImageDestinationCreateWithURL(tmpURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw CompressionError.heicTranscodeFailed
    }
    CGImageDestinationAddImage(dest, cgImage, nil)
    guard CGImageDestinationFinalize(dest) else {
        try? FileManager.default.removeItem(at: tmpURL)
        throw CompressionError.heicTranscodeFailed
    }
    return tmpURL
}

/// Downscale so display pixel width is `maxWidth` (same semantics as former `sips --resampleWidth`).
private func resizeImageMaxWidthUsingImageIO(source: URL, maxWidth: Int) throws -> URL {
    guard maxWidth > 0 else { throw CompressionError.imageResizeFailed }
    let cgImage = try cgImageDecodedOrientedFullSize(url: source)

    let w = cgImage.width
    let h = cgImage.height
    guard w > 0, h > 0 else { throw CompressionError.imageResizeFailed }

    let outW: Int
    let outH: Int
    if w <= maxWidth {
        outW = w
        outH = h
    } else {
        outW = maxWidth
        outH = max(1, Int((Double(h) * Double(maxWidth) / Double(w)).rounded()))
    }

    let tmpURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("dinky_resize_io_\(UUID().uuidString)")
        .appendingPathExtension("png")

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
    guard let ctx = CGContext(
        data: nil,
        width: outW,
        height: outH,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: bitmapInfo
    ) else {
        throw CompressionError.imageResizeFailed
    }
    ctx.interpolationQuality = .high
    ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: outW, height: outH))
    guard let scaled = ctx.makeImage() else {
        throw CompressionError.imageResizeFailed
    }

    guard let dest = CGImageDestinationCreateWithURL(tmpURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw CompressionError.imageResizeFailed
    }
    CGImageDestinationAddImage(dest, scaled, nil)
    guard CGImageDestinationFinalize(dest) else {
        try? FileManager.default.removeItem(at: tmpURL)
        throw CompressionError.imageResizeFailed
    }
    return tmpURL
}

/// HEIC output via ImageIO (decoded pixels only; no EXIF/XMP copied from source).
private func runHeicEncode(source: URL, quality: Int, output: URL) throws {
    let cgImage: CGImage
    do {
        cgImage = try cgImageDecodedOrientedFullSize(url: source)
    } catch {
        throw CompressionError.heicEncodeFailed
    }
    if FileManager.default.fileExists(atPath: output.path) {
        try? FileManager.default.removeItem(at: output)
    }
    guard let dest = CGImageDestinationCreateWithURL(output as CFURL, UTType.heic.identifier as CFString, 1, nil) else {
        throw CompressionError.heicEncodeFailed
    }
    let q = max(0, min(100, quality))
    let props: [CFString: Any] = [
        kCGImageDestinationLossyCompressionQuality: Double(q) / 100.0,
    ]
    CGImageDestinationAddImage(dest, cgImage, props as CFDictionary)
    guard CGImageDestinationFinalize(dest) else {
        try? FileManager.default.removeItem(at: output)
        throw CompressionError.heicEncodeFailed
    }
}

/// Animated GIF → animated WebP via ImageIO (`CGImageDestination`, no bundled encoder).
private func compressAnimatedGIFToWebP(
    source: URL,
    output: URL,
    quality: Int,
    strip: Bool,
    progress: (@Sendable (Float) -> Void)?
) throws {
    guard let src = CGImageSourceCreateWithURL(source as CFURL, nil) else {
        throw CompressionError.imageReadFailed
    }
    let frameCount = CGImageSourceGetCount(src)
    guard frameCount > 1 else { throw CompressionError.imageReadFailed }

    if FileManager.default.fileExists(atPath: output.path) {
        try? FileManager.default.removeItem(at: output)
    }

    let webpUTI = "org.webmproject.webp" as CFString
    guard let dst = CGImageDestinationCreateWithURL(output as CFURL, webpUTI, frameCount, nil) else {
        throw CompressionError.imageWriteFailed
    }

    let srcProps = CGImageSourceCopyProperties(src, nil) as? [CFString: Any]
    let gifProps = srcProps?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
    let loopCount = (gifProps?[kCGImagePropertyGIFLoopCount] as? Int) ?? 0
    let containerProps: [CFString: Any] = [
        kCGImagePropertyWebPDictionary: [
            kCGImagePropertyWebPLoopCount: loopCount,
        ] as CFDictionary,
    ]
    CGImageDestinationSetProperties(dst, containerProps as CFDictionary)

    let q = max(0, min(100, quality))
    let qualityCG = Double(q) / 100.0

    for i in 0..<frameCount {
        guard let frame = CGImageSourceCreateImageAtIndex(src, i, nil) else {
            try? FileManager.default.removeItem(at: output)
            throw CompressionError.imageReadFailed
        }

        let frameProps = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any]
        let gifFrameProps = frameProps?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        let delay = (gifFrameProps?[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
            ?? (gifFrameProps?[kCGImagePropertyGIFDelayTime] as? Double)
            ?? 0.1

        var outFrameProps: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: qualityCG,
            kCGImagePropertyWebPDictionary: [
                kCGImagePropertyWebPDelayTime: delay,
            ] as CFDictionary,
        ]
        if !strip, let fp = frameProps {
            if let exif = fp[kCGImagePropertyExifDictionary] {
                outFrameProps[kCGImagePropertyExifDictionary] = exif
            }
            if let iptc = fp[kCGImagePropertyIPTCDictionary] {
                outFrameProps[kCGImagePropertyIPTCDictionary] = iptc
            }
        }

        CGImageDestinationAddImage(dst, frame, outFrameProps as CFDictionary)
        progress?(Float(i + 1) / Float(frameCount))
    }

    guard CGImageDestinationFinalize(dst) else {
        try? FileManager.default.removeItem(at: output)
        throw CompressionError.imageWriteFailed
    }
}

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
        originalsAction: OriginalsAction = .keep,
        backupFolderURL: URL? = nil,
        isURLDownloadSource: Bool = false,
        smartQuality: Bool = false,
        contentTypeHint: String = "auto",
        /// When Smart Quality is on and the caller already classified (e.g. Auto format), skip a second Vision pass.
        preclassifiedContent: ContentType? = nil,
        /// Matches Settings “Batch speed” so `avifenc --jobs` doesn’t oversubscribe when many files run at once.
        parallelCompressionLimit: Int = 3,
        collisionNamingStyle: CollisionNamingStyle = .finderDuplicate,
        collisionCustomPattern: String = "",
        progressHandler: (@Sendable (Float) -> Void)? = nil
    ) async throws -> CompressionResult {
        let tTotal = CFAbsoluteTimeGetCurrent()
        let originalSize = fileSize(source)
        let sourceHasMultipleFrames = imageSourceHasMultipleFrames(url: source)
        let avifJobs = Self.avifEncoderJobCount(parallelLimit: parallelCompressionLimit)

        func report(_ v: Float) {
            progressHandler?(min(1, max(0, v)))
        }

        let outputURL = OutputPathUniqueness.uniqueOutputURL(
            desired: outputURL,
            sourceURL: source,
            style: collisionNamingStyle,
            customPattern: collisionCustomPattern
        )

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // Classify for Smart Quality on the **original** URL (EXIF intact), before branches that need quality.
        // Off-actor so Vision/pixel work doesn't serialize on this actor.
        let tClassify = CFAbsoluteTimeGetCurrent()
        let detected: ContentType?
        if smartQuality, let preclassifiedContent {
            detected = preclassifiedContent
        } else if smartQuality {
            detected = await Task.detached { ContentClassifier.classify(source) }.value
        } else {
            switch contentTypeHint {
            case "photo":             detected = .photo
            case "graphic", "ui":     detected = .graphic   // "ui" kept for legacy stored prefs
            case "mixed":             detected = .mixed
            default:                  detected = nil
            }
        }
        CompressionTiming.logPhase("image.classify", startedAt: tClassify)
        report(0.10)

        let isGIF = UTType(filenameExtension: source.pathExtension)?.conforms(to: .gif) == true
            || source.pathExtension.lowercased() == "gif"

        if format == .webp,
           sourceHasMultipleFrames,
           goals.maxFileSizeKB == nil,
           goals.maxWidth == nil,
           isGIF {
            let tEncodeAnim = CFAbsoluteTimeGetCurrent()
            let q = quality(for: format, content: detected)
            report(0.38)
            let ph = progressHandler
            try await Task.detached {
                try compressAnimatedGIFToWebP(
                    source: source,
                    output: outputURL,
                    quality: q,
                    strip: stripMetadata,
                    progress: { frac in ph?(0.38 + 0.62 * frac) }
                )
            }.value
            CompressionTiming.logPhase("image.encodeAnimatedWebP", startedAt: tEncodeAnim)
            report(1)

            guard FileManager.default.fileExists(atPath: outputURL.path) else {
                throw CompressionError.outputMissing
            }

            var recovery: URL?
            if isURLDownloadSource {
                try? FileManager.default.removeItem(at: source)
            } else {
                switch originalsAction {
                case .keep:
                    break
                case .trash:
                    recovery = try? OriginalsHandler.dispose(originalAt: source, action: .trash, backupFolder: nil)
                case .backup:
                    recovery = try? OriginalsHandler.dispose(originalAt: source, action: .backup, backupFolder: backupFolderURL)
                }
            }

            CompressionTiming.logPhase("image.compressTotal", startedAt: tTotal)
            return CompressionResult(
                outputURL: outputURL,
                originalSize: originalSize,
                outputSize: fileSize(outputURL),
                originalRecoveryURL: recovery,
                detectedContentType: detected,
                usedFirstFrameOnly: false
            )
        }

        // Step 1: HEIC/HEIF → PNG when needed for CLI encoders; HEIC output uses the source file when already HEIC/HEIF.
        let tHeic = CFAbsoluteTimeGetCurrent()
        let encoderInputURL = try await Task.detached {
            try encoderInputURLForImageCompression(source: source, outputFormat: format)
        }.value
        CompressionTiming.logPhase("image.heicTranscodeOrPassthrough", startedAt: tHeic)
        report(0.22)
        let encoderInputIsTemp = encoderInputURL != source
        defer { if encoderInputIsTemp { try? FileManager.default.removeItem(at: encoderInputURL) } }

        // Step 2: maybe resize
        let tResize = CFAbsoluteTimeGetCurrent()
        let workURL = try await maybeResize(source: encoderInputURL, maxWidth: goals.maxWidth)
        CompressionTiming.logPhase("image.resize", startedAt: tResize)
        report(0.33)
        let isTempWork = workURL != encoderInputURL
        defer { if isTempWork { try? FileManager.default.removeItem(at: workURL) } }

        // Step 3: compress — lossless formats skip quality targeting
        let tEncode = CFAbsoluteTimeGetCurrent()
        if format == .png {
            report(0.38)
            try await compressAtQuality(source: workURL, quality: 0,
                                        format: format, strip: stripMetadata, output: outputURL,
                                        content: detected, avifJobs: avifJobs)
            report(1)
        } else if let targetKB = goals.maxFileSizeKB {
            let floor = detected.flatMap { targetSizeFloor[$0] } ?? 10
            report(0.34)
            try await compressToTargetSize(
                source: workURL, targetBytes: Int64(targetKB) * 1024,
                format: format, strip: stripMetadata, output: outputURL,
                qualityFloor: floor, content: detected, avifJobs: avifJobs,
                progressHandler: progressHandler
            )
        } else {
            let q = quality(for: format, content: detected)
            // For graphics in WebP, near-lossless preserves edges that even
            // q=92 lossy softens. AVIF graphics handle crispness via 4:4:4 +
            // slower speed.
            let nl: Int? = (format == .webp && detected == .graphic) ? 60 : nil
            report(0.38)
            try await compressAtQuality(source: workURL, quality: q,
                                        format: format, strip: stripMetadata, output: outputURL,
                                        content: detected, nearLossless: nl, avifJobs: avifJobs)
            report(1)
        }
        CompressionTiming.logPhase("image.encode", startedAt: tEncode)

        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw CompressionError.outputMissing
        }

        var recovery: URL?
        if isURLDownloadSource {
            // Temp download — never trash/backup the temp path; remove silently.
            try? FileManager.default.removeItem(at: source)
        } else {
            switch originalsAction {
            case .keep:
                break
            case .trash:
                recovery = try? OriginalsHandler.dispose(originalAt: source, action: .trash, backupFolder: nil)
            case .backup:
                recovery = try? OriginalsHandler.dispose(originalAt: source, action: .backup, backupFolder: backupFolderURL)
            }
        }

        CompressionTiming.logPhase("image.compressTotal", startedAt: tTotal)
        return CompressionResult(outputURL: outputURL,
                                 originalSize: originalSize,
                                 outputSize: fileSize(outputURL),
                                 originalRecoveryURL: recovery,
                                 detectedContentType: detected,
                                 usedFirstFrameOnly: sourceHasMultipleFrames)
    }

    /// Resolve quality based on Smart Quality classification (if available).
    private func quality(for format: CompressionFormat, content: ContentType?) -> Int {
        if let content, let q = qualityByContent[content]?[format] { return q }
        return defaultQuality[format] ?? 82
    }

    /// `avifenc --jobs` scaled so N parallel encodes don’t each claim all cores (`--jobs all`).
    private static func avifEncoderJobCount(parallelLimit: Int) -> Int {
        let cores = ProcessInfo.processInfo.processorCount
        return max(1, cores / max(1, parallelLimit))
    }

    // MARK: - Resize (ImageIO only; oriented dimensions, no `sips`)

    private func maybeResize(source: URL, maxWidth: Int?) async throws -> URL {
        guard let maxWidth else { return source }

        guard let size = orientedPixelSize(url: source), Int(size.width) > maxWidth else {
            return source
        }

        return try await Task.detached {
            try resizeImageMaxWidthUsingImageIO(source: source, maxWidth: maxWidth)
        }.value
    }

    // MARK: - Quality binary search for file-size target

    private func compressToTargetSize(
        source: URL, targetBytes: Int64,
        format: CompressionFormat, strip: Bool, output: URL,
        qualityFloor: Int = 10,
        content: ContentType?,
        avifJobs: Int,
        progressHandler: (@Sendable (Float) -> Void)? = nil
    ) async throws {
        let fm = FileManager.default
        var encodeSteps = 0
        func bumpEncode() {
            encodeSteps += 1
            progressHandler?(min(0.97, 0.34 + Float(encodeSteps) * 0.048))
        }

        // Graphic + WebP: binary-search `-near_lossless` (40…100) before lossy `-q`.
        // Higher values = closer to lossless = larger files; we maximize nl that still fits the cap.
        if format == .webp, content == .graphic {
            var nlLo = 40, nlHi = 100
            var bestURL: URL?
            while nlLo <= nlHi {
                bumpEncode()
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
                progressHandler?(1)
                return
            }
        }

        var lo = qualityFloor, hi = 92
        var bestURL: URL?

        while lo <= hi {
            bumpEncode()
            let mid = (lo + hi) / 2
            let tmp = fm.temporaryDirectory
                .appendingPathComponent("dinky_q\(mid)_\(UUID().uuidString)")
                .appendingPathExtension(format.outputExtension)

            try await compressAtQuality(source: source, quality: mid, format: format, strip: strip, output: tmp, content: content, avifJobs: avifJobs)

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
            progressHandler?(1)
        } else {
            // Nothing met the target — use floor quality and let caller decide
            bumpEncode()
            try await compressAtQuality(source: source, quality: qualityFloor,
                                        format: format, strip: strip, output: output,
                                        content: content, avifJobs: avifJobs)
            progressHandler?(1)
        }
    }

    // MARK: - Format runners

    private func compressAtQuality(
        source: URL, quality: Int,
        format: CompressionFormat, strip: Bool, output: URL,
        content: ContentType?,
        nearLossless: Int? = nil,
        avifJobs: Int
    ) async throws {
        switch format {
        case .webp: try await runCwebp(source: source, quality: quality, strip: strip, output: output, content: content, nearLossless: nearLossless)
        case .avif: try await runAvifenc(source: source, quality: quality, strip: strip, output: output, content: content, avifJobs: avifJobs)
        case .png:  try await runOxipng(source: source, strip: strip, output: output)
        case .heic:
            try await Task.detached {
                try runHeicEncode(source: source, quality: quality, output: output)
            }.value
        }
    }

    private func runCwebp(source: URL, quality: Int, strip: Bool, output: URL, content: ContentType?, nearLossless: Int? = nil) async throws {
        let binary = try binaryURL("cwebp")
        let q = String(quality)
        var args: [String]
        if let nl = nearLossless {
            // Near-lossless: preprocesses pixel values for better compression
            // while keeping edges pixel-perfect. Best for graphics — UI,
            // illustrations, logos, anything with hard edges.
            // -q here controls compression effort, not visual quality.
            // `-m 4` and fewer passes keep Smart Quality responsive vs max-effort `-m 6`.
            args = ["-near_lossless", String(nl), "-m", "4", "-alpha_q", "100", "-exact", "-q", "100"]
        } else {
            // -preset must come first — it resets other flags.
            // `-m 4` / `-pass 4` (photo): faster than max method + 6 analysis passes with minimal visible change at our quality levels.
            switch content {
            case .photo:    args = ["-preset", "photo",   "-m", "4", "-sharp_yuv", "-pass", "4", "-af", "-q", q]
            case .graphic:  args = ["-preset", "text",    "-m", "4", "-sharp_yuv", "-alpha_q", "100", "-exact", "-q", q]
            case .mixed:    args = ["-preset", "picture", "-m", "4", "-sharp_yuv", "-q", q]
            case .none:     args = ["-preset", "picture", "-m", "4", "-q", q]
            }
        }
        if strip { args += ["-metadata", "none"] }
        args += [source.path, "-o", output.path]
        try await run(binary, args: args)
    }

    private func runAvifenc(source: URL, quality: Int, strip: Bool, output: URL, content: ContentType?, avifJobs: Int) async throws {
        let binary = try binaryURL("avifenc")
        let qColor = String(quality)
        let qAlpha = String(min(quality + 10, 100))
        let jobsArg = String(avifJobs)
        var args: [String]
        switch content {
        case .photo:    args = ["--speed", "6", "--yuv", "420", "--depth", "10", "--jobs", jobsArg, "--qcolor", qColor, "--qalpha", qAlpha]
        // Graphic: 4:4:4 keeps color edges sharp (no chroma subsampling).
        // Speed 5 balances edge quality with encode time (444 is already heavier than 420).
        case .graphic:  args = ["--speed", "5", "--yuv", "444", "--jobs", jobsArg, "--qcolor", qColor, "--qalpha", qAlpha]
        case .mixed:    args = ["--speed", "6", "--yuv", "422", "--depth", "10", "--jobs", jobsArg, "--qcolor", qColor, "--qalpha", qAlpha]
        case .none:     args = ["--speed", "6", "--yuv", "420", "--jobs", jobsArg, "--qcolor", qColor, "--qalpha", qAlpha]
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

    private func qpdfBinaryURL() -> URL? {
        let u = binDir.appendingPathComponent("qpdf")
        guard FileManager.default.isExecutableFile(atPath: u.path) else { return nil }
        return u
    }

    /// Structural/stream optimization via bundled `qpdf` (smaller output only when `originalSize` check passes in caller).
    private func runQpdfPreserve(
        source: URL,
        output: URL,
        stripMetadata: Bool,
        binary: URL,
        extraQpdfArgs: [String]
    ) async throws {
        var args: [String] = [
            source.path,
            output.path,
            "--object-streams=generate",
            "--compress-streams=y",
            "--recompress-flate",
            "--compression-level=9",
            "--remove-unreferenced-resources=yes",
            "--coalesce-contents",
            "--optimize-images",
        ]
        args.append(contentsOf: extraQpdfArgs)
        if stripMetadata {
            args.append(contentsOf: ["--remove-metadata", "--remove-info"])
        }
        do {
            try await run(binary, args: args)
        } catch {
            let withoutJpeg = extraQpdfArgs.filter { !$0.hasPrefix("--jpeg-quality=") }
            var fallback = [
                source.path,
                output.path,
                "--object-streams=generate",
                "--compress-streams=y",
                "--recompress-flate",
                "--compression-level=9",
                "--remove-unreferenced-resources=yes",
                "--coalesce-contents",
            ]
            fallback.append(contentsOf: withoutJpeg)
            if stripMetadata {
                fallback.append(contentsOf: ["--remove-metadata", "--remove-info"])
            }
            try await run(binary, args: fallback)
        }
    }

    func compressPDF(
        source: URL,
        outputMode: PDFOutputMode,
        quality: PDFQuality,
        grayscale: Bool,
        stripMetadata: Bool,
        outputURL: URL,
        flattenLastResort: Bool = false,
        flattenUltra: Bool = false,
        preserveQpdfSteps: [PDFPreserveQpdfStep] = [.base],
        targetBytes: Int64? = nil,
        resolutionDownsampling: Bool = false,
        progressHandler: (@Sendable (Float) -> Void)? = nil
    ) async throws -> CompressionResult {
        let tPDF = CFAbsoluteTimeGetCurrent()
        let originalSize = fileSize(source)

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var winningPreserveQpdfStepId: String? = nil
        switch outputMode {
        case .preserveStructure:
            progressHandler?(0.06)
            let fm = FileManager.default
            var usedQpdf = false
            if let qpdfBin = qpdfBinaryURL() {
                let steps = preserveQpdfSteps.isEmpty ? [PDFPreserveQpdfStep.base] : preserveQpdfSteps
                let n = max(steps.count, 1)
                var bestQpdfURL: URL? = nil
                var bestQpdfSize: Int64 = originalSize
                for (idx, step) in steps.enumerated() {
                    let qpdfTmp = fm.temporaryDirectory.appendingPathComponent("dinky_qpdf_\(UUID().uuidString).pdf")
                    progressHandler?(0.06 + 0.08 * Float(idx + 1) / Float(n))
                    do {
                        try await runQpdfPreserve(
                            source: source,
                            output: qpdfTmp,
                            stripMetadata: stripMetadata,
                            binary: qpdfBin,
                            extraQpdfArgs: step.extraArgs
                        )
                        let qSz = fileSize(qpdfTmp)
                        if qSz > 0 && qSz < bestQpdfSize {
                            if let prev = bestQpdfURL { try? fm.removeItem(at: prev) }
                            bestQpdfURL = qpdfTmp
                            bestQpdfSize = qSz
                            winningPreserveQpdfStepId = step.id
                            // Without a size target, first improvement is good enough.
                            // With a target, keep trying steps until we're under it.
                            let targetMet = targetBytes.map { qSz <= $0 } ?? true
                            if targetMet { break }
                        } else {
                            try? fm.removeItem(at: qpdfTmp)
                        }
                    } catch {
                        try? fm.removeItem(at: qpdfTmp)
                        continue
                    }
                }
                if let best = bestQpdfURL {
                    if fm.fileExists(atPath: outputURL.path) { try fm.removeItem(at: outputURL) }
                    try fm.moveItem(at: best, to: outputURL)
                    usedQpdf = true
                }
            }
            if !usedQpdf {
                let ph = progressHandler
                try await Task.detached {
                    try PDFCompressor.preserveStructure(
                        source: source,
                        stripMetadata: stripMetadata,
                        outputURL: outputURL,
                        progress: ph
                    )
                }.value
            } else {
                progressHandler?(1)
            }

            if resolutionDownsampling, fm.fileExists(atPath: outputURL.path),
               let structureDoc = PDFDocument(url: outputURL) {
                let dsURL = fm.temporaryDirectory.appendingPathComponent("dinky_pdf_ds_\(UUID().uuidString).pdf")
                if let mixed = PDFImageDownsampler.downsample(source: source, structureDoc: structureDoc, stripMetadata: stripMetadata),
                   mixed.write(to: dsURL) {
                    let dsSz = fileSize(dsURL)
                    if dsSz > 0 && dsSz < fileSize(outputURL) {
                        try? fm.removeItem(at: outputURL)
                        try? fm.moveItem(at: dsURL, to: outputURL)
                    } else {
                        try? fm.removeItem(at: dsURL)
                    }
                }
            }
        case .flattenPages:
            let ph = progressHandler
            let ultra = flattenUltra
            let lastResort = flattenLastResort && !ultra
            try await Task.detached {
                try PDFCompressor.compressFlattened(
                    source: source, quality: quality, grayscale: grayscale,
                    stripMetadata: stripMetadata, outputURL: outputURL,
                    lastResortFlatten: lastResort,
                    ultraLastResortFlatten: ultra,
                    progress: ph
                )
            }.value
        }
        CompressionTiming.logPhase("pdf.compress.\(outputMode == .flattenPages ? "flatten" : "preserve")", startedAt: tPDF)

        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw CompressionError.outputMissing
        }

        let outSz = fileSize(outputURL)
        let chainIds = preserveQpdfSteps.isEmpty ? "base" : preserveQpdfSteps.map(\.id).joined(separator: ">")
        PDFCompressionMetrics.logOutcome(
            outputMode: outputMode,
            originalBytes: originalSize,
            outputBytes: outSz,
            flattenLastResort: flattenLastResort,
            flattenUltra: flattenUltra,
            preserveQpdfChain: outputMode == .preserveStructure ? chainIds : nil,
            preserveQpdfWinningStep: winningPreserveQpdfStepId
        )

        return CompressionResult(outputURL: outputURL,
                                 originalSize: originalSize,
                                 outputSize: outSz,
                                 detectedContentType: nil)
    }

    // MARK: - Video compression

    func compressVideo(
        source: URL,
        quality: VideoQuality,
        codec: VideoCodecFamily,
        removeAudio: Bool,
        maxResolutionLines: Int? = nil,
        outputURL: URL,
        videoContentType: VideoContentType? = nil,
        progressHandler: (@Sendable (Float) -> Void)? = nil
    ) async throws -> CompressionResult {
        try await compressVideo(
            asset: VideoCompressor.makeURLAsset(url: source),
            source: source,
            quality: quality,
            codec: codec,
            removeAudio: removeAudio,
            maxResolutionLines: maxResolutionLines,
            outputURL: outputURL,
            videoContentType: videoContentType,
            progressHandler: progressHandler
        )
    }

    /// Reuses a pre-built ``AVURLAsset`` (e.g. shared with ``VideoSmartQuality``) to avoid reopening the file.
    /// - Parameter maxResolutionLines: Optional output-height cap (mirrors images' Max width). `nil` keeps source resolution.
    /// - Parameter videoContentType: When already known (Smart Quality classified it), surfaced in the result for the UI chip.
    func compressVideo(
        asset: AVURLAsset,
        source: URL,
        quality: VideoQuality,
        codec: VideoCodecFamily,
        removeAudio: Bool,
        maxResolutionLines: Int? = nil,
        outputURL: URL,
        videoContentType: VideoContentType? = nil,
        progressHandler: (@Sendable (Float) -> Void)? = nil
    ) async throws -> CompressionResult {
        let originalSize = fileSize(source)

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let resolved = try await VideoCompressor.compress(
            asset: asset,
            sourceForMetadata: source,
            quality: quality,
            codec: codec,
            removeAudio: removeAudio,
            maxResolutionLines: maxResolutionLines,
            outputURL: outputURL,
            progressHandler: progressHandler
        )

        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw CompressionError.outputMissing
        }

        return CompressionResult(
            outputURL: outputURL,
            originalSize: originalSize,
            outputSize: fileSize(outputURL),
            detectedContentType: nil,
            videoDuration: resolved.durationSeconds,
            videoContentType: videoContentType,
            videoIsHDR: resolved.isHDR,
            videoEffectiveCodec: resolved.codec
        )
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
}
