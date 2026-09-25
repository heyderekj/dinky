import CoreGraphics
import DinkyCoreShared
import Foundation
import ImageIO
import UniformTypeIdentifiers
import os

// MARK: - Phase debug (matches app Console filtering intent)

enum DinkyImageCorePhaseLog {
    private static let log = Logger(
        subsystem: "com.dinky.dinkycore",
        category: "ImageCompression"
    )
    static func logPhase(_ name: String, startedAt: CFAbsoluteTime) {
        let elapsed = CFAbsoluteTimeGetCurrent() - startedAt
        log.debug("\(name, privacy: .public) \(String(format: "%.3f", elapsed))s")
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

// MARK: - ImageIO decode

private enum DinkyImageIOConstants {
    static var orientedFullImageDecode: [CFString: Any] {
        [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 32_768,
            kCGImageSourceShouldCacheImmediately: true,
        ]
    }
}

/// Full-resolution decode with EXIF orientation applied (matches Smart Quality thumbnails).
private func cgImageDecodedOrientedFullSize(url: URL) throws -> CGImage {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          CGImageSourceGetCount(src) > 0 else {
        throw DinkyImageCompressionError.imageResizeFailed
    }
    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(src, 0, DinkyImageIOConstants.orientedFullImageDecode as CFDictionary) else {
        throw DinkyImageCompressionError.imageResizeFailed
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

/// Decode non-PNG sources when needed; skip when output is HEIC (ImageIO reads HEIC directly).
private func encoderInputURLForImageCompression(source: URL, outputFormat: CompressionFormat) throws -> URL {
    let ext = source.pathExtension.lowercased()
    if outputFormat == .heic, ext == "heic" || ext == "heif" {
        return source
    }
    if outputFormat == .png {
        guard ext != "png" else { return source }
        return try decodeImageToPNG(source: source)
    }
    return try heicTranscodeToPNGIfNeeded(source: source)
}

/// Lossless pixel decode to PNG so `oxipng` can read the file.
private func decodeImageToPNG(source: URL) throws -> URL {
    let cgImage: CGImage
    do {
        cgImage = try cgImageDecodedOrientedFullSize(url: source)
    } catch {
        throw DinkyImageCompressionError.imageReadFailed
    }

    let tmpURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("dinky_decode_\(UUID().uuidString)")
        .appendingPathExtension("png")

    guard let dest = CGImageDestinationCreateWithURL(tmpURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw DinkyImageCompressionError.imageWriteFailed
    }
    CGImageDestinationAddImage(dest, cgImage, nil)
    guard CGImageDestinationFinalize(dest) else {
        try? FileManager.default.removeItem(at: tmpURL)
        throw DinkyImageCompressionError.imageWriteFailed
    }
    return tmpURL
}

/// HEIC/HEIF → PNG when bundled CLI encoders need a readable path.
private func heicTranscodeToPNGIfNeeded(source: URL) throws -> URL {
    let ext = source.pathExtension.lowercased()
    guard ext == "heic" || ext == "heif" else { return source }
    do {
        return try decodeImageToPNG(source: source)
    } catch {
        throw DinkyImageCompressionError.heicTranscodeFailed
    }
}

/// Downscale so display pixel width is `maxWidth` (same semantics as former `sips --resampleWidth`).
private func resizeImageMaxWidthUsingImageIO(source: URL, maxWidth: Int) throws -> (URL, ImageResizeInfo?) {
    guard maxWidth > 0 else { throw DinkyImageCompressionError.imageResizeFailed }
    let cgImage = try cgImageDecodedOrientedFullSize(url: source)

    let w = cgImage.width
    let h = cgImage.height
    guard w > 0, h > 0 else { throw DinkyImageCompressionError.imageResizeFailed }

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

    let colorSpace: CGColorSpace = cgImage.colorSpace
        ?? CGColorSpace(name: CGColorSpace.sRGB)
        ?? CGColorSpaceCreateDeviceRGB()
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
        throw DinkyImageCompressionError.imageResizeFailed
    }
    ctx.interpolationQuality = CGInterpolationQuality.high
    ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: outW, height: outH))
    guard let scaled = ctx.makeImage() else {
        throw DinkyImageCompressionError.imageResizeFailed
    }

    guard let dest = CGImageDestinationCreateWithURL(tmpURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw DinkyImageCompressionError.imageResizeFailed
    }
    CGImageDestinationAddImage(dest, scaled, nil)
    guard CGImageDestinationFinalize(dest) else {
        try? FileManager.default.removeItem(at: tmpURL)
        throw DinkyImageCompressionError.imageResizeFailed
    }
    let info = w > maxWidth
        ? ImageResizeInfo(originalWidth: w, originalHeight: h, outputWidth: outW, outputHeight: outH)
        : nil
    return (tmpURL, info)
}

/// HEIC output via ImageIO (decoded pixels only; no EXIF/XMP copied from source).
private func runHeicEncode(source: URL, quality: Int, output: URL) throws {
    let cgImage: CGImage
    do {
        cgImage = try cgImageDecodedOrientedFullSize(url: source)
    } catch {
        throw DinkyImageCompressionError.heicEncodeFailed
    }
    if FileManager.default.fileExists(atPath: output.path) {
        try? FileManager.default.removeItem(at: output)
    }
    guard let dest = CGImageDestinationCreateWithURL(output as CFURL, UTType.heic.identifier as CFString, 1, nil) else {
        throw DinkyImageCompressionError.heicEncodeFailed
    }
    let q = max(0, min(100, quality))
    let props: [CFString: Any] = [
        kCGImageDestinationLossyCompressionQuality: Double(q) / 100.0,
    ]
    CGImageDestinationAddImage(dest, cgImage, props as CFDictionary)
    guard CGImageDestinationFinalize(dest) else {
        try? FileManager.default.removeItem(at: output)
        throw DinkyImageCompressionError.heicEncodeFailed
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
        throw DinkyImageCompressionError.imageReadFailed
    }
    let frameCount = CGImageSourceGetCount(src)
    guard frameCount > 1 else { throw DinkyImageCompressionError.imageReadFailed }

    if FileManager.default.fileExists(atPath: output.path) {
        try? FileManager.default.removeItem(at: output)
    }

    let webpUTI = "org.webmproject.webp" as CFString
    guard let dst = CGImageDestinationCreateWithURL(output as CFURL, webpUTI, frameCount, nil) else {
        throw DinkyImageCompressionError.imageWriteFailed
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
            throw DinkyImageCompressionError.imageReadFailed
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
        throw DinkyImageCompressionError.imageWriteFailed
    }
}

public actor DinkyImageCompression {
    private let binDir: URL

    public init(binDirectory: URL) {
        self.binDir = binDirectory
    }

    // MARK: - Public

    public func compress(
        source: URL,
        format: CompressionFormat,
        goals: CompressionGoals,
        stripMetadata: Bool,
        outputURL: URL,
        smartQuality: Bool = false,
        contentTypeHint: String = "auto",
        /// When Smart Quality is on and the caller already classified (e.g. Auto format), skip a second Vision pass.
        preclassifiedContent: ContentType? = nil,
        /// Matches Settings “Batch speed” so `avifenc --jobs` doesn’t oversubscribe when many files run at once.
        parallelCompressionLimit: Int = 3,
        collisionNamingStyle: CollisionNamingStyle = .finderDuplicate,
        collisionCustomPattern: String = "",
        /// When set, use this 0...100 for lossy formats instead of Smart Quality / defaults (near-lossless heuristics for graphics are skipped).
        qualityOverride: Int? = nil,
        chromaSubsampling: ChromaSubsampling = .auto,
        webpLossless: Bool = false,
        pngOutputMode: PNGOutputMode = .lossless,
        progressHandler: (@Sendable (Float) -> Void)? = nil
    ) async throws -> DinkyImageCompressionResult {
        let tTotal = CFAbsoluteTimeGetCurrent()
        let chroma = smartQuality ? ChromaSubsampling.auto : chromaSubsampling
        let webpLL = smartQuality ? false : webpLossless
        let pngMode = smartQuality ? PNGOutputMode.lossless : pngOutputMode
        let originalSize = fileSize(source)
        let sourceHasMultipleFrames = imageSourceHasMultipleFrames(url: source)
        let avifJobs = Self.avifEncoderJobCount(parallelLimit: parallelCompressionLimit)

        func report(_ v: Float) {
            progressHandler?(min(1, max(0, v)))
        }

        var outputURL = OutputPathUniqueness.uniqueOutputURL(
            desired: outputURL,
            sourceURL: source,
            style: collisionNamingStyle,
            customPattern: collisionCustomPattern
        )

        // Output would overwrite the source (Replace original, same format): encode to a temp file
        // instead. The caller decides whether the result is worth keeping and only then swaps it in,
        // so a result that's thrown away never destroys the original.
        var stagedDestination: URL?
        if outputURL.standardizedFileURL.path == source.standardizedFileURL.path {
            stagedDestination = outputURL
            outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("dinky_img_\(UUID().uuidString)")
                .appendingPathExtension(format.outputExtension)
        }

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
            detected = ContentClassifier.classify(source)
        } else {
            switch contentTypeHint {
            case "photo":             detected = .photo
            case "graphic", "ui":     detected = .graphic   // "ui" kept for legacy stored prefs
            case "mixed":             detected = .mixed
            default:                  detected = nil
            }
        }
        DinkyImageCorePhaseLog.logPhase("image.classify", startedAt: tClassify)
        report(0.10)

        let isGIF = UTType(filenameExtension: source.pathExtension)?.conforms(to: .gif) == true
            || source.pathExtension.lowercased() == "gif"

        if format == .webp,
           sourceHasMultipleFrames,
           goals.maxFileSizeKB == nil,
           goals.maxWidth == nil,
           isGIF {
            let tEncodeAnim = CFAbsoluteTimeGetCurrent()
            let q: Int = {
                if let o = qualityOverride { return max(0, min(100, o)) }
                return quality(for: format, content: detected)
            }()
            report(0.38)
            outputURL = OutputPathUniqueness.refreshUniqueOutput(
                currentCandidate: outputURL,
                sourceURL: source,
                style: collisionNamingStyle,
                customPattern: collisionCustomPattern
            )
            let ph = progressHandler
            try compressAnimatedGIFToWebP(
                source: source,
                output: outputURL,
                quality: q,
                strip: stripMetadata,
                progress: { frac in ph?(0.38 + 0.62 * frac) }
            )
            DinkyImageCorePhaseLog.logPhase("image.encodeAnimatedWebP", startedAt: tEncodeAnim)
            report(1)

            guard FileManager.default.fileExists(atPath: outputURL.path) else {
                throw DinkyImageCompressionError.outputMissing
            }

            DinkyImageCorePhaseLog.logPhase("image.compressTotal", startedAt: tTotal)
            return DinkyImageCompressionResult(
                outputURL: outputURL,
                originalSize: originalSize,
                outputSize: fileSize(outputURL),
                detectedContentType: detected,
                usedFirstFrameOnly: false,
                appliedChromaSubsampling: nil,
                appliedWebpLossless: webpLL,
                appliedPngOutputMode: nil,
                stagedDestinationURL: stagedDestination
            )
        }

        // Step 1: HEIC/HEIF → PNG when needed for CLI encoders; HEIC output uses the source file when already HEIC/HEIF.
        let tHeic = CFAbsoluteTimeGetCurrent()
        let encoderInputURL = try encoderInputURLForImageCompression(source: source, outputFormat: format)
        DinkyImageCorePhaseLog.logPhase("image.heicTranscodeOrPassthrough", startedAt: tHeic)
        report(0.22)
        let encoderInputIsTemp = encoderInputURL != source
        defer { if encoderInputIsTemp { try? FileManager.default.removeItem(at: encoderInputURL) } }

        // Step 2: maybe resize
        let tResize = CFAbsoluteTimeGetCurrent()
        let (workURL, resize) = try maybeResize(source: encoderInputURL, maxWidth: goals.maxWidth)
        DinkyImageCorePhaseLog.logPhase("image.resize", startedAt: tResize)
        report(0.33)
        let isTempWork = workURL != encoderInputURL
        defer { if isTempWork { try? FileManager.default.removeItem(at: workURL) } }

        // Step 3: compress — lossless formats skip quality targeting
        outputURL = OutputPathUniqueness.refreshUniqueOutput(
            currentCandidate: outputURL,
            sourceURL: source,
            style: collisionNamingStyle,
            customPattern: collisionCustomPattern
        )
        let tEncode = CFAbsoluteTimeGetCurrent()
        let unlimitedQuality: Int = {
            if let o = qualityOverride { return max(0, min(100, o)) }
            return quality(for: format, content: detected)
        }()
        // For graphics in WebP, near-lossless preserves edges that even
        // q=92 lossy softens. AVIF graphics handle crispness via 4:4:4 +
        // slower speed. Skipped when lossless WebP is requested.
        let unlimitedNearLossless: Int? =
            (qualityOverride == nil && !webpLL && format == .webp && detected == .graphic) ? 60 : nil
        var appliedChroma: String?
        var appliedPngMode: String?
        if format == .png {
            report(0.38)
            appliedPngMode = pngMode.rawValue
            try await encodePNG(
                source: workURL, strip: stripMetadata, output: outputURL,
                mode: pngMode
            )
            report(1)
        } else if let targetKB = goals.maxFileSizeKB {
            let floor = detected.flatMap { targetSizeFloor[$0] } ?? 10
            report(0.34)
            try await compressToTargetSize(
                source: workURL, targetBytes: Int64(targetKB) * 1024,
                format: format, strip: stripMetadata, output: &outputURL,
                unlimitedQuality: unlimitedQuality, unlimitedNearLossless: unlimitedNearLossless,
                qualityFloor: floor, content: detected, avifJobs: avifJobs,
                chromaSubsampling: chroma,
                webpLossless: webpLL,
                sourceURLForUniqueness: source,
                collisionNamingStyle: collisionNamingStyle,
                collisionCustomPattern: collisionCustomPattern,
                progressHandler: progressHandler
            )
            if format == .avif {
                appliedChroma = resolvedAvifYUV(chromaSubsampling: chroma, content: detected)
            }
        } else {
            report(0.38)
            try await compressAtQuality(
                source: workURL, quality: unlimitedQuality,
                format: format, strip: stripMetadata, output: outputURL,
                content: detected, nearLossless: unlimitedNearLossless, avifJobs: avifJobs,
                chromaSubsampling: chroma, webpLossless: webpLL
            )
            if format == .avif {
                appliedChroma = resolvedAvifYUV(chromaSubsampling: chroma, content: detected)
            }
            report(1)
        }
        DinkyImageCorePhaseLog.logPhase("image.encode", startedAt: tEncode)

        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw DinkyImageCompressionError.outputMissing
        }

        DinkyImageCorePhaseLog.logPhase("image.compressTotal", startedAt: tTotal)
        return DinkyImageCompressionResult(
            outputURL: outputURL,
            originalSize: originalSize,
            outputSize: fileSize(outputURL),
            detectedContentType: detected,
            usedFirstFrameOnly: sourceHasMultipleFrames,
            appliedChromaSubsampling: appliedChroma,
            appliedWebpLossless: format == .webp && webpLL,
            appliedPngOutputMode: appliedPngMode,
            resize: resize,
            stagedDestinationURL: stagedDestination
        )
    }

    /// Resolve the `--yuv` flag that will be (or was) passed to avifenc.
    private func resolvedAvifYUV(chromaSubsampling: ChromaSubsampling, content: ContentType?) -> String {
        if let flag = chromaSubsampling.avifYUVFlag { return flag }
        switch content {
        case .photo:   return "420"
        case .graphic: return "444"
        case .mixed:   return "422"
        case .none:    return "420"
        }
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

    private func maybeResize(source: URL, maxWidth: Int?) throws -> (URL, ImageResizeInfo?) {
        guard let maxWidth else { return (source, nil) }

        guard let size = orientedPixelSize(url: source), Int(size.width) > maxWidth else {
            return (source, nil)
        }

        let (url, info) = try resizeImageMaxWidthUsingImageIO(source: source, maxWidth: maxWidth)
        return (url, info)
    }

    // MARK: - Quality binary search for file-size target

    /// A size limit is a ceiling, not a target: encode exactly as with no limit first and only
    /// give up quality when that doesn't fit. Searching for the *highest* quality under the limit
    /// made roomy limits produce files bigger than no limit — often bigger than the original.
    private func compressToTargetSize(
        source: URL, targetBytes: Int64,
        format: CompressionFormat, strip: Bool, output: inout URL,
        unlimitedQuality: Int, unlimitedNearLossless: Int?,
        qualityFloor: Int = 10,
        content: ContentType?,
        avifJobs: Int,
        chromaSubsampling: ChromaSubsampling,
        webpLossless: Bool,
        sourceURLForUniqueness: URL,
        collisionNamingStyle: CollisionNamingStyle,
        collisionCustomPattern: String,
        progressHandler: (@Sendable (Float) -> Void)? = nil
    ) async throws {
        let fm = FileManager.default
        var encodeSteps = 0
        func bumpEncode() {
            encodeSteps += 1
            progressHandler?(min(0.97, 0.34 + Float(encodeSteps) * 0.048))
        }

        // Largest-quality attempt that fits, and the smallest attempt that didn't. When nothing
        // fits, the smallest miss is kept instead of re-encoding at the floor: lossy WebP at low
        // quality can be several times larger than near-lossless for graphics, and a limit must
        // never leave a file bigger than no limit would have.
        var chosen: URL?
        var smallestMiss: URL?
        func recordMiss(_ url: URL) {
            if let current = smallestMiss, fileSize(current) <= fileSize(url) {
                try? fm.removeItem(at: url)
            } else {
                if let current = smallestMiss { try? fm.removeItem(at: current) }
                smallestMiss = url
            }
        }
        func recordFit(_ url: URL) {
            if let previous = chosen { try? fm.removeItem(at: previous) }
            chosen = url
        }
        func scratchURL(_ label: String) -> URL {
            fm.temporaryDirectory
                .appendingPathComponent("dinky_\(label)_\(UUID().uuidString)")
                .appendingPathExtension(format.outputExtension)
        }

        bumpEncode()
        let unlimited = scratchURL("unlimited")
        try await compressAtQuality(
            source: source, quality: unlimitedQuality, format: format, strip: strip, output: unlimited,
            content: content, nearLossless: unlimitedNearLossless, avifJobs: avifJobs,
            chromaSubsampling: chromaSubsampling, webpLossless: webpLossless
        )
        // Lossless WebP has no quality to trade, so it's kept whatever its size.
        if webpLossless || fileSize(unlimited) <= targetBytes {
            recordFit(unlimited)
        } else {
            recordMiss(unlimited)
        }

        // Graphic + WebP (lossy): binary-search `-near_lossless` below the unlimited setting before
        // lossy `-q`. Higher values = closer to lossless = larger files; maximize nl that fits.
        if chosen == nil, let nlCeiling = unlimitedNearLossless {
            var nlLo = 40, nlHi = nlCeiling - 1
            while nlLo <= nlHi {
                bumpEncode()
                let mid = (nlLo + nlHi) / 2
                let tmp = scratchURL("nl\(mid)")
                try await runCwebp(
                    source: source, quality: 100, strip: strip, output: tmp,
                    content: content, nearLossless: mid, webpLossless: false
                )
                if fileSize(tmp) <= targetBytes {
                    recordFit(tmp)
                    nlLo = mid + 1
                } else {
                    recordMiss(tmp)
                    nlHi = mid - 1
                }
            }
        }

        if chosen == nil {
            // The unlimited encode was this exact lossy quality unless it used near-lossless.
            var lo = qualityFloor
            var hi = unlimitedNearLossless == nil ? unlimitedQuality - 1 : unlimitedQuality
            while lo <= hi {
                bumpEncode()
                let mid = (lo + hi) / 2
                let tmp = scratchURL("q\(mid)")
                try await compressAtQuality(
                    source: source, quality: mid, format: format, strip: strip, output: tmp,
                    content: content, avifJobs: avifJobs,
                    chromaSubsampling: chromaSubsampling, webpLossless: webpLossless
                )
                if fileSize(tmp) <= targetBytes {
                    recordFit(tmp)
                    lo = mid + 1     // fits — try higher quality
                } else {
                    recordMiss(tmp)
                    hi = mid - 1     // too big — lower quality
                }
            }
        }

        guard let keep = chosen ?? smallestMiss else { throw DinkyImageCompressionError.outputMissing }
        if let miss = smallestMiss, miss != keep { try? fm.removeItem(at: miss) }
        output = try OutputPathUniqueness.moveTempItemToUniqueOutput(
            temp: keep,
            desiredOutput: output,
            sourceURL: sourceURLForUniqueness,
            style: collisionNamingStyle,
            customPattern: collisionCustomPattern,
            fileManager: fm
        )
        progressHandler?(1)
    }

    // MARK: - Format runners

    private func compressAtQuality(
        source: URL, quality: Int,
        format: CompressionFormat, strip: Bool, output: URL,
        content: ContentType?,
        nearLossless: Int? = nil,
        avifJobs: Int,
        chromaSubsampling: ChromaSubsampling = .auto,
        webpLossless: Bool = false
    ) async throws {
        switch format {
        case .webp:
            try await runCwebp(
                source: source, quality: quality, strip: strip, output: output,
                content: content, nearLossless: nearLossless, webpLossless: webpLossless
            )
        case .avif:
            try await runAvifenc(
                source: source, quality: quality, strip: strip, output: output,
                content: content, avifJobs: avifJobs, chromaSubsampling: chromaSubsampling
            )
        case .png:
            try await runOxipng(source: source, strip: strip, output: output)
        case .heic:
            try runHeicEncode(source: source, quality: quality, output: output)
        }
    }

    private func runCwebp(
        source: URL, quality: Int, strip: Bool, output: URL,
        content: ContentType?, nearLossless: Int? = nil, webpLossless: Bool = false
    ) async throws {
        let binary = try binaryURL("cwebp")
        let q = String(quality)
        var args: [String]
        if webpLossless {
            args = ["-lossless", "-z", "6", "-exact", "-m", "4"]
        } else if let nl = nearLossless {
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
            case .mixed:    args = ["-preset", "picture", "-m", "4", "-sharp_yuv", "-af", "-alpha_q", "100", "-exact", "-q", q]
            case .none:     args = ["-preset", "picture", "-m", "4", "-sharp_yuv", "-af", "-q", q]
            }
        }
        args += ["-metadata", strip ? "icc" : "all"]
        args += [source.path, "-o", output.path]
        try await run(binary, args: args)
    }

    private func runAvifenc(
        source: URL, quality: Int, strip: Bool, output: URL,
        content: ContentType?, avifJobs: Int,
        chromaSubsampling: ChromaSubsampling = .auto
    ) async throws {
        let binary = try binaryURL("avifenc")
        let qColor = String(quality)
        let qAlpha = String(min(quality + 10, 100))
        let jobsArg = String(avifJobs)
        let yuv = chromaSubsampling.avifYUVFlag ?? resolvedAvifYUV(chromaSubsampling: .auto, content: content)
        var args: [String]
        switch yuv {
        case "420":
            args = ["--speed", "5", "--yuv", "420", "--depth", "10", "--jobs", jobsArg, "--qcolor", qColor, "--qalpha", qAlpha]
        case "422":
            args = ["--speed", "5", "--yuv", "422", "--depth", "10", "--jobs", jobsArg, "--qcolor", qColor, "--qalpha", qAlpha]
        case "444":
            args = ["--speed", "5", "--yuv", "444", "--jobs", jobsArg, "--qcolor", qColor, "--qalpha", qAlpha]
        default:
            args = ["--speed", "6", "--yuv", "420", "--depth", "10", "--jobs", jobsArg, "--qcolor", qColor, "--qalpha", qAlpha]
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
        if strip { args += ["--strip", "safe"] }
        args += ["--out", output.path, output.path]
        try await run(binary, args: args)
    }

    // MARK: - PNG (lossless + optional palette)

    private func encodePNG(source: URL, strip: Bool, output: URL, mode: PNGOutputMode) async throws {
        let fm = FileManager.default
        if mode == .optimized,
           let cgImage = try? cgImageDecodedOrientedFullSize(url: source),
           let paletteURL = try? writePalettePNGIfApplicable(cgImage: cgImage) {
            defer { try? fm.removeItem(at: paletteURL) }
            let paletteOxipng = fm.temporaryDirectory
                .appendingPathComponent("dinky_png_pal_\(UUID().uuidString).png")
            defer { try? fm.removeItem(at: paletteOxipng) }
            try await runOxipng(source: paletteURL, strip: strip, output: paletteOxipng)

            let fullOxipng = fm.temporaryDirectory
                .appendingPathComponent("dinky_png_full_\(UUID().uuidString).png")
            defer { try? fm.removeItem(at: fullOxipng) }
            try await runOxipng(source: source, strip: strip, output: fullOxipng)

            if fileSize(paletteOxipng) < fileSize(fullOxipng) {
                try fm.copyItem(at: paletteOxipng, to: output)
                return
            }
        }
        try await runOxipng(source: source, strip: strip, output: output)
    }

    /// Writes PNG-8 when the image is fully opaque and has ≤256 unique RGB colors.
    private func writePalettePNGIfApplicable(cgImage: CGImage) throws -> URL {
        guard let rgba = readOpaqueRGBA(cgImage: cgImage) else {
            throw DinkyImageCompressionError.imageWriteFailed
        }
        var colorToIndex: [RGBTriple: UInt8] = [:]
        colorToIndex.reserveCapacity(min(256, rgba.count))
        var palette: [RGBTriple] = []
        palette.reserveCapacity(256)
        var indices = [UInt8]()
        indices.reserveCapacity(rgba.count)
        for px in rgba {
            if let idx = colorToIndex[px] {
                indices.append(idx)
            } else {
                guard palette.count < 256 else {
                    throw DinkyImageCompressionError.imageWriteFailed
                }
                let idx = UInt8(palette.count)
                palette.append(px)
                colorToIndex[px] = idx
                indices.append(idx)
            }
        }
        guard !palette.isEmpty else { throw DinkyImageCompressionError.imageWriteFailed }

        var paletteBytes = [UInt8]()
        paletteBytes.reserveCapacity(palette.count * 3)
        for c in palette {
            paletteBytes.append(c.r)
            paletteBytes.append(c.g)
            paletteBytes.append(c.b)
        }
        let base = CGColorSpaceCreateDeviceRGB()
        guard let indexedSpace = CGColorSpace(
            indexedBaseSpace: base,
            last: palette.count - 1,
            colorTable: paletteBytes
        ) else {
            throw DinkyImageCompressionError.imageWriteFailed
        }

        let width = cgImage.width
        let height = cgImage.height
        let indexData = Data(indices)
        guard let provider = CGDataProvider(data: indexData as CFData),
              let indexedImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 8,
                bytesPerRow: width,
                space: indexedSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            throw DinkyImageCompressionError.imageWriteFailed
        }

        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dinky_palette_\(UUID().uuidString).png")
        guard let dest = CGImageDestinationCreateWithURL(tmpURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw DinkyImageCompressionError.imageWriteFailed
        }
        CGImageDestinationAddImage(dest, indexedImage, nil)
        guard CGImageDestinationFinalize(dest) else {
            try? FileManager.default.removeItem(at: tmpURL)
            throw DinkyImageCompressionError.imageWriteFailed
        }
        return tmpURL
    }

    private struct RGBTriple: Hashable {
        let r, g, b: UInt8
    }

    /// Returns nil when any pixel has alpha &lt; 255.
    private func readOpaqueRGBA(cgImage: CGImage) -> [RGBTriple]? {
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return nil }

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var buffer = [UInt8](repeating: 0, count: height * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue

        guard let ctx = buffer.withUnsafeMutableBytes({ rawPtr -> CGContext? in
            guard let base = rawPtr.baseAddress else { return nil }
            return CGContext(
                data: base,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            )
        }) else { return nil }

        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var pixels = [RGBTriple]()
        pixels.reserveCapacity(width * height)
        for i in 0..<(width * height) {
            let off = i * 4
            let a = buffer[off + 3]
            if a != 255 { return nil }
            pixels.append(RGBTriple(r: buffer[off], g: buffer[off + 1], b: buffer[off + 2]))
        }
        return pixels
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
                    cont.resume(throwing: DinkyImageCompressionError.processFailed(p.terminationStatus, stderr))
                }
            }
            do    { try process.run() }
            catch { cont.resume(throwing: error) }
        }
    }

    private func binaryURL(_ name: String) throws -> URL {
        let url = binDir.appendingPathComponent(name)
        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            throw DinkyImageCompressionError.binaryNotFound(name)
        }
        return url
    }

    private func fileSize(_ url: URL) -> Int64 {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) } ?? 0
    }
}
