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
    case medium = "medium"
    case high   = "high"

    var id: String { rawValue }

    /// Decode a persisted raw value safely. Migrates the legacy `"low"` tier
    /// (removed because it produced unacceptable artifacts for a quality-first
    /// compressor) to `.medium` — the closest remaining tier, which preserves
    /// the user's "smaller" intent without silently promoting them to `.high`.
    /// Anything else falls back to `.medium` too.
    static func resolve(_ rawValue: String) -> VideoQuality {
        if let v = VideoQuality(rawValue: rawValue) { return v }
        return .medium
    }

    var displayName: String {
        switch self {
        // Display labels are decoupled from raw values so persisted prefs/presets keep loading.
        // "Balanced" replaces the old "Medium" — with `.low` removed it's the more honest framing
        // (smaller file, no obvious quality loss), not a "lower" tier.
        case .medium: return "Balanced"
        case .high:   return "High"
        }
    }

    func exportPreset(for codec: VideoCodecFamily) -> String {
        switch codec {
        case .h264:
            switch self {
            case .medium: return AVAssetExportPreset1280x720
            case .high:   return AVAssetExportPresetHighestQuality
            }
        case .hevc:
            switch self {
            case .medium: return AVAssetExportPresetHEVC1920x1080
            case .high:   return AVAssetExportPresetHEVCHighestQuality
            }
        }
    }

    /// Export preset that downscales to a chosen output height. Picks the closest *available* Apple preset and rounds
    /// up to the next supported height when no exact match exists. Returns `nil` for invalid input.
    static func exportPreset(forMaxHeight lines: Int, codec: VideoCodecFamily) -> String? {
        guard lines > 0 else { return nil }
        switch codec {
        case .h264:
            switch lines {
            case ...480:        return AVAssetExportPreset640x480
            case 481...720:     return AVAssetExportPreset1280x720
            case 721...1080:    return AVAssetExportPreset1920x1080
            default:            return AVAssetExportPreset3840x2160
            }
        case .hevc:
            switch lines {
            case ...1080:       return AVAssetExportPresetHEVC1920x1080
            default:            return AVAssetExportPresetHEVC3840x2160
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
        case .medium: base = 0.55
        case .high:   base = 0.75
        }
        // HEVC is ~40% more efficient than H.264, so we can squeeze a bit more.
        return codec == .hevc ? base * 0.85 : base
    }

    /// Bitrate (bits/sec) below which we treat the source as already lean for this tier.
    fileprivate var skipIfEstimatedBitrateBelow: Double {
        switch self {
        case .medium: return 5_000_000
        case .high:   return 8_000_000
        }
    }

    var description: String {
        switch self {
        case .medium: return "Smaller file. No obvious quality loss."
        case .high:   return "Closest to source. Minimal trim."
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

    /// What `compress` actually used (after HDR-driven codec overrides). Lets callers report it in the UI.
    struct ResolvedExport: Sendable {
        let durationSeconds: Double?
        /// Codec we actually exported with — may differ from the requested codec when the source is HDR
        /// (HDR is force-promoted to HEVC because H.264 cannot carry HDR metadata in our pipeline).
        let codec: VideoCodecFamily
        let isHDR: Bool
    }

    static func compress(
        source: URL,
        quality: VideoQuality,
        codec: VideoCodecFamily,
        removeAudio: Bool,
        maxResolutionLines: Int? = nil,
        outputURL: URL,
        progressHandler: (@Sendable (Float) -> Void)? = nil
    ) async throws -> ResolvedExport {
        try await compress(
            asset: makeURLAsset(url: source),
            sourceForMetadata: source,
            quality: quality,
            codec: codec,
            removeAudio: removeAudio,
            maxResolutionLines: maxResolutionLines,
            outputURL: outputURL,
            progressHandler: progressHandler
        )
    }

    /// - Parameter maxResolutionLines: Optional output-height cap (mirrors images' Max width). `nil` keeps source resolution.
    static func compress(
        asset: AVURLAsset,
        sourceForMetadata: URL,
        quality: VideoQuality,
        codec: VideoCodecFamily,
        removeAudio: Bool,
        maxResolutionLines: Int? = nil,
        outputURL: URL,
        progressHandler: (@Sendable (Float) -> Void)? = nil
    ) async throws -> ResolvedExport {
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

        // HDR safety guard: H.264 in our export pipeline does not carry HDR transfer / color
        // metadata, so an HDR (HLG / PQ / Dolby Vision) source compressed as H.264 produces a
        // washed / clipped SDR output. Force HEVC for HDR sources regardless of the user's choice.
        let isHDR = await sourceIsHDR(track: videoTrack, formatDescriptions: formatDescriptions)
        let effectiveCodec: VideoCodecFamily = isHDR ? .hevc : codec

        let sourceMatchesTarget = codecMatchesTarget(primarySub, target: effectiveCodec)

        if shouldSkipReencode(
            removeAudio: removeAudio,
            quality: quality,
            codec: effectiveCodec,
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
        let resolvedPreset: String
        if let lines = maxResolutionLines, let p = VideoQuality.exportPreset(forMaxHeight: lines, codec: effectiveCodec) {
            resolvedPreset = p
        } else {
            resolvedPreset = quality.exportPreset(for: effectiveCodec)
        }
        let presetName = usePassthrough ? AVAssetExportPresetPassthrough : resolvedPreset

        guard let session = AVAssetExportSession(asset: exportAsset, presetName: presetName) else {
            throw VideoCompressionError.exportSessionUnavailable
        }

        session.shouldOptimizeForNetworkUse = true

        // Two-pass encoding for `.medium` — gives the rate-controller a chance to allocate bits where
        // they matter. `.high` already targets minimal compression so the extra pass doesn't help much.
        if !usePassthrough, quality == .medium {
            session.canPerformMultiplePassesOverSourceMediaData = true
        }

        if !usePassthrough, originalBytes > 0 {
            let factor = quality.targetSizeFactor(for: effectiveCodec)
            let target = Int64(Double(originalBytes) * factor)
            var bounded = max(Int64(512 * 1024), min(originalBytes - 1024, target))
            bounded = min(bounded, originalBytes - 1024)
            bounded = max(Int64(512 * 1024), bounded)
            session.fileLengthLimit = bounded
        }

        try await exportWithProgress(session: session, outputURL: outputURL, progressHandler: progressHandler)
        return ResolvedExport(
            durationSeconds: CMTimeGetSeconds(duration),
            codec: effectiveCodec,
            isHDR: isHDR
        )
    }

    /// Cheap HDR check: prefer the modern `.containsHDRVideo` characteristic, fall back to inspecting
    /// the format description's transfer function (HLG / PQ) for older / unusual files.
    private static func sourceIsHDR(track: AVAssetTrack, formatDescriptions: [CMFormatDescription]) async -> Bool {
        if let characteristics = try? await track.load(.mediaCharacteristics),
           characteristics.contains(.containsHDRVideo) {
            return true
        }
        for desc in formatDescriptions {
            if let ext = CMFormatDescriptionGetExtension(desc, extensionKey: kCMFormatDescriptionExtension_TransferFunction) as? String {
                let hlg = kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String
                let pq  = kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String
                if ext == hlg || ext == pq { return true }
            }
        }
        return false
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

        if codec == .hevc, isHEVC {
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
