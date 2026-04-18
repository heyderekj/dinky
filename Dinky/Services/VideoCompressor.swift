import Foundation
import AVFoundation

/// Video codec family for MP4 export (container stays `.mp4`).
enum VideoCodecFamily: String, CaseIterable, Identifiable {
    case h264
    case hevc

    var id: String { rawValue }

    var chipLabel: String {
        switch self {
        case .h264: return "H.264"
        case .hevc: return "H.265"
        }
    }

    var description: String {
        switch self {
        case .h264: return "Best compatibility — older devices, web, and TVs."
        case .hevc: return "Smaller files — great on recent Macs, iPhone, and iPad."
        }
    }
}

enum VideoQuality: String, CaseIterable, Identifiable {
    case low    = "low"
    case medium = "medium"
    case high   = "high"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .low:    return "Low"
        case .medium: return "Medium"
        case .high:   return "High"
        }
    }

    func exportPreset(for codec: VideoCodecFamily) -> String {
        switch codec {
        case .h264:
            switch self {
            case .low:    return AVAssetExportPresetLowQuality
            case .medium: return AVAssetExportPreset1280x720
            case .high:   return AVAssetExportPreset1920x1080
            }
        case .hevc:
            switch self {
            case .low:
                // Apple provides no sub-1080p **HEVC** export preset; non-`HEVC*` presets use H.264.
                // Differentiate low from medium via `targetSizeFactor` (tighter `fileLengthLimit`).
                return AVAssetExportPresetHEVC1920x1080
            case .medium: return AVAssetExportPresetHEVC1920x1080
            case .high:   return AVAssetExportPresetHEVCHighestQuality
            }
        }
    }

    /// Target output size as a fraction of the source. Combined with
    /// `AVAssetExportSession.fileLengthLimit`, this forces AVFoundation to
    /// pick a bitrate that actually shrinks the file rather than leaning on
    /// a preset's fixed bitrate (which can produce a *larger* file when the
    /// source is already efficiently encoded).
    func targetSizeFactor(for codec: VideoCodecFamily) -> Double {
        let base: Double
        switch self {
        case .low:    base = 0.30
        case .medium: base = 0.55
        case .high:   base = 0.75
        }
        // HEVC is ~40% more efficient than H.264, so we can squeeze a bit more.
        var factor = codec == .hevc ? base * 0.85 : base
        // No HEVC 720p preset without falling back to H.264 — tighten the size cap for low.
        if codec == .hevc, self == .low {
            factor *= 0.72
        }
        return factor
    }

    /// Bitrate (bits/sec) below which we treat the source as already lean for this tier.
    fileprivate var skipIfEstimatedBitrateBelow: Double {
        switch self {
        case .low:    return 2_500_000
        case .medium: return 5_000_000
        case .high:   return 8_000_000
        }
    }

    var description: String {
        switch self {
        case .low:    return "Smaller file, softer detail."
        case .medium: return "Balanced size and clarity."
        case .high:   return "Highest detail, larger file."
        }
    }
}

enum VideoCompressor {

    /// One-shot export: avoid polluting AVFoundation’s persistent asset cache.
    static func makeURLAsset(url: URL) -> AVURLAsset {
        let options: [String: Any] = [
            // Not always exposed to Swift on macOS; string matches `AVURLAssetUsesNoPersistentCacheKey`.
            "AVURLAssetUsesNoPersistentCacheKey": true,
            AVURLAssetPreferPreciseDurationAndTimingKey: false,
        ]
        return AVURLAsset(url: url, options: options)
    }

    static func compress(
        source: URL,
        quality: VideoQuality,
        codec: VideoCodecFamily,
        removeAudio: Bool,
        outputURL: URL,
        progressHandler: (@Sendable (Float) -> Void)? = nil
    ) async throws -> Double? {
        try await compress(
            asset: makeURLAsset(url: source),
            sourceForMetadata: source,
            quality: quality,
            codec: codec,
            removeAudio: removeAudio,
            outputURL: outputURL,
            progressHandler: progressHandler
        )
    }

    static func compress(
        asset: AVURLAsset,
        sourceForMetadata: URL,
        quality: VideoQuality,
        codec: VideoCodecFamily,
        removeAudio: Bool,
        outputURL: URL,
        progressHandler: (@Sendable (Float) -> Void)? = nil
    ) async throws -> Double? {
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            throw VideoCompressionError.exportSessionUnavailable
        }

        let duration = try await asset.load(.duration)
        let formatDescriptions = try await videoTrack.load(.formatDescriptions)
        let primarySub: CMVideoCodecType? = formatDescriptions.first.map { CMFormatDescriptionGetMediaSubType($0) }
        let estimatedRate = try await videoTrack.load(.estimatedDataRate)
        let originalBytes = (try? sourceForMetadata.resourceValues(forKeys: [.fileSizeKey]).fileSize)
            .flatMap { Int64($0) } ?? 0

        let sourceMatchesTarget = codecMatchesTarget(primarySub, target: codec)

        if shouldSkipReencode(
            removeAudio: removeAudio,
            quality: quality,
            codec: codec,
            sourceMatchesTarget: sourceMatchesTarget,
            isHEVC: primarySub == kCMVideoCodecType_HEVC,
            originalBytes: originalBytes,
            estimatedRate: estimatedRate
        ) {
            throw VideoCompressionError.alreadyOptimized
        }

        let exportAsset: AVAsset
        if removeAudio {
            let composition = AVMutableComposition()
            let compositionTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
            try compositionTrack?.insertTimeRange(
                CMTimeRange(start: .zero, duration: duration),
                of: videoTrack,
                at: .zero
            )
            exportAsset = composition
        } else {
            exportAsset = asset
        }

        let usePassthrough = removeAudio && sourceMatchesTarget
        let presetName = usePassthrough ? AVAssetExportPresetPassthrough : quality.exportPreset(for: codec)

        guard let session = AVAssetExportSession(asset: exportAsset, presetName: presetName) else {
            throw VideoCompressionError.exportSessionUnavailable
        }

        session.shouldOptimizeForNetworkUse = true

        if !usePassthrough, quality == .low || quality == .medium {
            session.canPerformMultiplePassesOverSourceMediaData = true
        }

        if !usePassthrough, originalBytes > 0 {
            let factor = quality.targetSizeFactor(for: codec)
            let target = Int64(Double(originalBytes) * factor)
            var bounded = max(Int64(512 * 1024), min(originalBytes - 1024, target))
            if let minBytes = try await minimumFileLengthLimitBytes(
                quality: quality,
                codec: codec,
                videoTrack: videoTrack,
                duration: duration
            ) {
                bounded = max(bounded, minBytes)
            }
            bounded = min(bounded, originalBytes - 1024)
            bounded = max(Int64(512 * 1024), bounded)
            session.fileLengthLimit = bounded
        }

        try await exportWithProgress(session: session, outputURL: outputURL, progressHandler: progressHandler)
        return CMTimeGetSeconds(duration)
    }

    /// Runs `export` concurrently with `states(updateInterval:)` for progress updates.
    private static func exportWithProgress(
        session: AVAssetExportSession,
        outputURL: URL,
        progressHandler: (@Sendable (Float) -> Void)?
    ) async throws {
        if let progressHandler {
            let monitor = Task {
                for await state in session.states(updateInterval: 0.1) {
                    guard !Task.isCancelled else { break }
                    switch state {
                    case .pending, .waiting:
                        break
                    case .exporting(let progress):
                        progressHandler(Float(progress.fractionCompleted))
                    @unknown default:
                        break
                    }
                }
            }
            defer { monitor.cancel() }
            try await session.export(to: outputURL, as: .mp4)
            progressHandler(1)
        } else {
            try await session.export(to: outputURL, as: .mp4)
        }
    }

    /// Prevents ultra-low bitrates on busy 1080p+ footage when `fileLengthLimit` is very tight (especially HEVC low).
    private static func minimumFileLengthLimitBytes(
        quality: VideoQuality,
        codec: VideoCodecFamily,
        videoTrack: AVAssetTrack,
        duration: CMTime
    ) async throws -> Int64? {
        guard quality == .low else { return nil }
        let seconds = CMTimeGetSeconds(duration)
        guard seconds > 0, seconds.isFinite else { return nil }

        let size = try await videoTrack.load(.naturalSize)
        let transform = try await videoTrack.load(.preferredTransform)
        let transformed = size.applying(transform)
        let w = abs(transformed.width)
        let h = abs(transformed.height)
        guard w >= 1, h >= 1 else { return nil }

        var fps = Double(try await videoTrack.load(.nominalFrameRate))
        if fps <= 0 || !fps.isFinite { fps = 30 }

        let pixelsPerSecond = Double(w * h) * fps
        let bppFloor: Double
        switch codec {
        case .hevc: bppFloor = 0.04
        case .h264: bppFloor = 0.08
        }
        let minBitrate = pixelsPerSecond * bppFloor
        return Int64(ceil((minBitrate * seconds) / 8.0))
    }

    private static func codecMatchesTarget(_ sub: CMVideoCodecType?, target: VideoCodecFamily) -> Bool {
        guard let sub else { return false }
        switch target {
        case .h264:
            return sub == kCMVideoCodecType_H264
                || sub == kCMVideoCodecType_MPEG4Video
        case .hevc:
            return sub == kCMVideoCodecType_HEVC
        }
    }

    private static func shouldSkipReencode(
        removeAudio: Bool,
        quality: VideoQuality,
        codec: VideoCodecFamily,
        sourceMatchesTarget: Bool,
        isHEVC: Bool,
        originalBytes: Int64,
        estimatedRate: Float
    ) -> Bool {
        if removeAudio { return false }

        if codec == .hevc, quality != .low, isHEVC {
            if estimatedRate > 0, Double(estimatedRate) >= quality.skipIfEstimatedBitrateBelow * 1.5 {
                return false
            }
            return true
        }

        if !sourceMatchesTarget { return false }

        if originalBytes > 0, originalBytes < 1_048_576 {
            return true
        }

        let rate = Double(estimatedRate)
        if estimatedRate > 0, rate < quality.skipIfEstimatedBitrateBelow {
            return true
        }

        return false
    }
}

enum VideoCompressionError: LocalizedError {
    case exportSessionUnavailable
    case exportFailed(String)
    case alreadyOptimized

    var errorDescription: String? {
        switch self {
        case .exportSessionUnavailable: return "Could not create export session for this video."
        case .exportFailed(let msg):    return "Video export failed: \(msg)"
        case .alreadyOptimized:         return "Video is already about as small as it’ll get for this setting."
        }
    }
}
