import AVFoundation
import CoreGraphics
import DinkyCoreImage
import DinkyCoreShared
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct CompressionResult {
    let outputURL: URL
    let originalSize: Int64
    let outputSize: Int64
    let detectedContentType: ContentType?
    var videoDuration: Double? = nil
    var videoContentType: VideoContentType? = nil
    var videoIsHDR: Bool = false
    var videoEffectiveCodec: VideoCodecFamily? = nil
    /// Duration in seconds when the job was audio (or reuse for display).
    var audioDurationSeconds: Double? = nil
    var usedFirstFrameOnly: Bool = false
    /// Set when an image was downscaled to fit a width limit.
    var imageResize: ImageResizeInfo? = nil
    /// Where an image encoded to a temp file belongs (the source's own path) if it's kept.
    var stagedDestinationURL: URL? = nil
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
    case audioConversionFailed(String)
    case audioNoTrack
    case audioUnsupportedSource(String)

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
        case .audioConversionFailed(let msg):
            return msg
        case .audioNoTrack:
            return String(localized: "No audio track was found in this file.", comment: "Audio conversion error.")
        case .audioUnsupportedSource(let cc):
            return String(localized: "This audio file uses a codec (\(cc)) that macOS can’t decode. Try converting it with another tool first.",
                          comment: "Audio import error for AMR/3GP and other codecs Apple doesn’t support.")
        }
    }
}

actor CompressionService {
    static let shared = CompressionService()
    private let binDir: URL
    private let imagePipeline: DinkyImageCompression

    private init() {
        guard let url = Bundle.main.resourceURL else {
            fatalError("Bundle.main.resourceURL is nil — app bundle is malformed")
        }
        self.binDir = url
        self.imagePipeline = DinkyImageCompression(binDirectory: url)
    }

    func compress(
        source: URL,
        format: CompressionFormat,
        goals: CompressionGoals,
        stripMetadata: Bool,
        outputURL: URL,
        smartQuality: Bool = false,
        contentTypeHint: String = "auto",
        preclassifiedContent: ContentType? = nil,
        parallelCompressionLimit: Int = 3,
        collisionNamingStyle: CollisionNamingStyle = .finderDuplicate,
        collisionCustomPattern: String = "",
        chromaSubsampling: ChromaSubsampling = .auto,
        webpLossless: Bool = false,
        pngOutputMode: PNGOutputMode = .lossless,
        progressHandler: (@Sendable (Float) -> Void)? = nil
    ) async throws -> CompressionResult {
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        do {
            let r = try await imagePipeline.compress(
                source: source,
                format: format,
                goals: goals,
                stripMetadata: stripMetadata,
                outputURL: outputURL,
                smartQuality: smartQuality,
                contentTypeHint: contentTypeHint,
                preclassifiedContent: preclassifiedContent,
                parallelCompressionLimit: parallelCompressionLimit,
                collisionNamingStyle: collisionNamingStyle,
                collisionCustomPattern: collisionCustomPattern,
                qualityOverride: nil,
                chromaSubsampling: chromaSubsampling,
                webpLossless: webpLossless,
                pngOutputMode: pngOutputMode,
                progressHandler: progressHandler
            )
            return CompressionResult(
                outputURL: r.outputURL,
                originalSize: r.originalSize,
                outputSize: r.outputSize,
                detectedContentType: r.detectedContentType,
                usedFirstFrameOnly: r.usedFirstFrameOnly,
                imageResize: r.resize,
                stagedDestinationURL: r.stagedDestinationURL
            )
        } catch let e as DinkyImageCompressionError {
            throw e.asAppError()
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
        collisionNamingStyle: CollisionNamingStyle = .finderDuplicate,
        collisionCustomPattern: String = "",
        chromaSubsampling: ChromaSubsampling = .auto,
        webpLossless: Bool = false,
        pngOutputMode: PNGOutputMode = .lossless,
        progressHandler: (@Sendable (Float) -> Void)? = nil
    ) async throws -> CompressionResult {
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let qpdf = DinkyEncoderPath.qpdfExecutable(inBinDirectory: binDir)
        let pdfResult = try await DinkyPDFPipeline.compress(
            source: source,
            outputMode: outputMode,
            quality: quality,
            grayscale: grayscale,
            stripMetadata: stripMetadata,
            outputURL: outputURL,
            flattenLastResort: flattenLastResort,
            flattenUltra: flattenUltra,
            preserveQpdfSteps: preserveQpdfSteps,
            targetBytes: targetBytes,
            resolutionDownsampling: resolutionDownsampling,
            collisionNamingStyle: collisionNamingStyle,
            collisionCustomPattern: collisionCustomPattern,
            qpdfBinary: qpdf,
            progressHandler: progressHandler
        )
        return CompressionResult(
            outputURL: pdfResult.outputURL,
            originalSize: pdfResult.originalSize,
            outputSize: pdfResult.outputSize,
            detectedContentType: nil
        )
    }

    // MARK: - Video compression

    func compressVideo(
        source: URL,
        quality: VideoQuality,
        codec: VideoCodecFamily,
        removeAudio: Bool,
        maxResolutionLines: Int? = nil,
        maxFPSEnabled: Bool = false,
        storedMaxFPS: Int = VideoFPSCapPreset.defaultStoredFPS,
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
            maxFPSEnabled: maxFPSEnabled,
            storedMaxFPS: storedMaxFPS,
            outputURL: outputURL,
            videoContentType: videoContentType,
            progressHandler: progressHandler
        )
    }

    /// Reuses a pre-built ``AVURLAsset`` (e.g. shared with ``VideoSmartQuality``) to avoid reopening the file.
    /// - Parameter maxResolutionLines: Optional output-height cap (mirrors images' Max width). `nil` keeps source resolution.
    /// - Parameter maxFPSEnabled: When true, down-cap frame rate using ``storedMaxFPS`` when source nominal FPS is higher.
    func compressVideo(
        asset: AVURLAsset,
        source: URL,
        quality: VideoQuality,
        codec: VideoCodecFamily,
        removeAudio: Bool,
        maxResolutionLines: Int? = nil,
        maxFPSEnabled: Bool = false,
        storedMaxFPS: Int = VideoFPSCapPreset.defaultStoredFPS,
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
            maxFPSEnabled: maxFPSEnabled,
            storedMaxFPS: storedMaxFPS,
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

    // MARK: - Audio conversion

    func compressAudio(
        source: URL,
        targetFormat: AudioConversionFormat,
        qualityTier: AudioConversionQualityTier,
        outputURL: URL,
        progressHandler: (@Sendable (Float) -> Void)? = nil
    ) async throws -> CompressionResult {
        let originalSize = fileSize(source)
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let lameExecutable: URL? = {
            guard targetFormat == .mp3 else { return nil }
            return DinkyEncoderPath.lameExecutable(inBinDirectory: binDir)
        }()

        if targetFormat == .mp3, lameExecutable == nil {
            throw CompressionError.binaryNotFound("lame")
        }

        let resolved: AudioCompressor.Resolved
        do {
            resolved = try await AudioCompressor.convert(
                source: source,
                targetFormat: targetFormat,
                qualityTier: qualityTier,
                lameExecutable: lameExecutable,
                outputURL: outputURL,
                progressHandler: progressHandler
            )
        } catch let e as AudioCompressionError {
            throw mapAudioCompressionError(e)
        }

        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw CompressionError.outputMissing
        }

        return CompressionResult(
            outputURL: outputURL,
            originalSize: originalSize,
            outputSize: fileSize(outputURL),
            detectedContentType: nil,
            audioDurationSeconds: resolved.durationSeconds
        )
    }

    private func mapAudioCompressionError(_ e: AudioCompressionError) -> CompressionError {
        switch e {
        case .noAudioTrack: return .audioNoTrack
        case .lameExecutableRequired: return .binaryNotFound("lame")
        case .afconvertFailed(let m): return .audioConversionFailed(m)
        case .unsupportedSourceCodec(let cc): return .audioUnsupportedSource(cc)
        case .unreadableSource:
            return .audioConversionFailed(String(
                localized: "Couldn’t read audio data from this file.",
                comment: "Audio import error when AVFoundation can’t open the asset."
            ))
        }
    }

    // MARK: - Helpers

    private func fileSize(_ url: URL) -> Int64 {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { Int64($0) } ?? 0
    }
}
