import AVFoundation
import DinkyCoreShared
import Foundation

/// Video codec family for MP4 export (container stays `.mp4`).
public enum VideoCodecFamily: String, CaseIterable, Identifiable, Sendable, Codable {
    case h264
    case hevc

    public var id: String { rawValue }

    public var chipLabel: String {
        switch self {
        case .h264: return "H.264"
        case .hevc: return "H.265"
        }
    }

    public var description: String {
        switch self {
        case .h264: return "Best compatibility — older devices, web, and TVs."
        case .hevc: return "Smaller files — great on recent Macs, iPhone, and iPad."
        }
    }
}

public enum VideoQuality: String, CaseIterable, Identifiable, Sendable, Codable {
    case medium = "medium"
    case high = "high"

    public var id: String { rawValue }

    /// Decode a persisted raw value safely. Migrates the legacy `"low"` tier
    /// (removed because it produced unacceptable artifacts for a quality-first
    /// compressor) to `.medium` — the closest remaining tier, which preserves
    /// the user's "smaller" intent without silently promoting them to `.high`.
    /// Anything else falls back to `.medium` too.
    public static func resolve(_ rawValue: String) -> VideoQuality {
        if let v = VideoQuality(rawValue: rawValue) { return v }
        return .medium
    }

    public var displayName: String {
        switch self {
        case .medium: return "Balanced"
        case .high: return "High"
        }
    }

    public func exportPreset(for codec: VideoCodecFamily) -> String {
        switch codec {
        case .h264:
            switch self {
            // Same 1080p as HEVC Balanced: the 720p preset quietly shrank every 1080p video.
            case .medium: return AVAssetExportPreset1920x1080
            case .high: return AVAssetExportPresetHighestQuality
            }
        case .hevc:
            switch self {
            case .medium: return AVAssetExportPresetHEVC1920x1080
            case .high: return AVAssetExportPresetHEVCHighestQuality
            }
        }
    }

    /// Export preset that downscales to a chosen output height. Picks the closest *available* Apple preset and rounds
    /// up to the next supported height when no exact match exists. Returns `nil` for invalid input.
    public static func exportPreset(forMaxHeight lines: Int, codec: VideoCodecFamily) -> String? {
        guard lines > 0 else { return nil }
        switch codec {
        case .h264:
            switch lines {
            // 640×480 fits 16:9 video to 640×360; 960×540 is the nearest preset that gives ~480 lines.
            case ...540: return AVAssetExportPreset960x540
            case 541...720: return AVAssetExportPreset1280x720
            case 721...1080: return AVAssetExportPreset1920x1080
            default: return AVAssetExportPreset3840x2160
            }
        case .hevc:
            switch lines {
            case ...1080: return AVAssetExportPresetHEVC1920x1080
            default: return AVAssetExportPresetHEVC3840x2160
            }
        }
    }

    /// Target output size as a fraction of the source. Combined with
    /// `AVAssetExportSession.fileLengthLimit`, this forces AVFoundation to
    /// pick a bitrate that actually shrinks the file rather than leaning on
    /// a preset's fixed bitrate (which can produce a *larger* file when the
    /// source is already efficiently encoded).
    public func targetSizeFactor(for codec: VideoCodecFamily, sourceIsHEVC: Bool = false) -> Double {
        let base: Double
        switch self {
        case .medium: base = 0.55
        case .high: base = 0.75
        }
        // HEVC is ~40% more efficient than H.264, so we can squeeze a bit more.
        if codec == .hevc { return base * 0.85 }
        // HEVC → H.264 needs ~1.6× the bits for the same picture; 55% of an HEVC file's bytes
        // starved the less efficient codec.
        return sourceIsHEVC ? base * Self.hevcToH264BitrateRatio : base
    }

    static let hevcToH264BitrateRatio = 1.6

    /// Bitrate (bits/sec) below which we treat the source as already lean for this tier.
    var skipIfEstimatedBitrateBelow: Double {
        switch self {
        case .medium: return 5_000_000
        case .high: return 8_000_000
        }
    }

    public var description: String {
        switch self {
        case .medium: return "Smaller file. No obvious quality loss."
        case .high: return "Closest to source. Minimal trim."
        }
    }
}

public enum VideoCompressor: Sendable {

    /// One-shot export: avoid polluting AVFoundation’s persistent asset cache.
    public static func makeURLAsset(url: URL) -> AVURLAsset {
        let options: [String: Any] = [
            "AVURLAssetUsesNoPersistentCacheKey": true,
            AVURLAssetPreferPreciseDurationAndTimingKey: false,
        ]
        return AVURLAsset(url: url, options: options)
    }

    /// What `compress` actually used (after HDR-driven codec overrides). Lets callers report it in the UI.
    public struct ResolvedExport: Sendable {
        public let durationSeconds: Double?
        public let codec: VideoCodecFamily
        public let isHDR: Bool

        public init(durationSeconds: Double?, codec: VideoCodecFamily, isHDR: Bool) {
            self.durationSeconds = durationSeconds
            self.codec = codec
            self.isHDR = isHDR
        }
    }

    public static func compress(
        source: URL,
        quality: VideoQuality,
        codec: VideoCodecFamily,
        removeAudio: Bool,
        maxResolutionLines: Int? = nil,
        maxFPSEnabled: Bool = false,
        storedMaxFPS: Int = VideoFPSCapPreset.defaultStoredFPS,
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
            maxFPSEnabled: maxFPSEnabled,
            storedMaxFPS: storedMaxFPS,
            outputURL: outputURL,
            progressHandler: progressHandler
        )
    }

    /// - Parameter maxResolutionLines: Optional output-height cap (mirrors images' Max width). `nil` keeps source resolution.
    public static func compress(
        asset: AVURLAsset,
        sourceForMetadata: URL,
        quality: VideoQuality,
        codec: VideoCodecFamily,
        removeAudio: Bool,
        maxResolutionLines: Int? = nil,
        maxFPSEnabled: Bool = false,
        storedMaxFPS: Int = VideoFPSCapPreset.defaultStoredFPS,
        outputURL: URL,
        progressHandler: (@Sendable (Float) -> Void)? = nil
    ) async throws -> ResolvedExport {
        let tExport = CFAbsoluteTimeGetCurrent()
        defer { CompressionTiming.logPhase("video.export", startedAt: tExport) }

        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            throw VideoCompressionError.exportSessionUnavailable
        }

        let duration = try await asset.load(.duration)
        let formatDescriptions = try await videoTrack.load(.formatDescriptions)
        let primarySub: CMVideoCodecType? = formatDescriptions.first.map { CMFormatDescriptionGetMediaSubType($0) }
        let estimatedRate = try await videoTrack.load(.estimatedDataRate)
        let nominalFPS = try await videoTrack.load(.nominalFrameRate)
        let effectiveFPSCap = VideoFPSCapPreset.effectiveCapFPS(
            enabled: maxFPSEnabled,
            storedFPS: storedMaxFPS,
            sourceNominalFPS: nominalFPS
        )
        let needsFPSComposition = effectiveFPSCap != nil

        let originalBytes = (try? sourceForMetadata.resourceValues(forKeys: [.fileSizeKey]).fileSize)
            .flatMap { Int64($0) } ?? 0

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
        ), !needsFPSComposition {
            throw VideoCompressionError.alreadyOptimized
        }

        let exportAsset: AVAsset
        var videoComposition: AVVideoComposition?
        if needsFPSComposition, let cap = effectiveFPSCap {
            let composition = AVMutableComposition()
            guard let compositionVideo = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                throw VideoCompressionError.exportSessionUnavailable
            }
            try compositionVideo.insertTimeRange(
                CMTimeRange(start: .zero, duration: duration),
                of: videoTrack,
                at: .zero
            )
            if !removeAudio {
                let audioTracks = try await asset.loadTracks(withMediaType: .audio)
                if let srcAudio = audioTracks.first,
                   let compositionAudio = composition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                   ) {
                    try compositionAudio.insertTimeRange(
                        CMTimeRange(start: .zero, duration: duration),
                        of: srcAudio,
                        at: .zero
                    )
                }
            }
            exportAsset = composition
            videoComposition = try await makeFPSCapVideoComposition(
                compositionVideoTrack: compositionVideo,
                sourceVideoTrack: videoTrack,
                duration: duration,
                cappedFPS: cap
            )
        } else if removeAudio {
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

        let usePassthrough = removeAudio && sourceMatchesTarget && !needsFPSComposition
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
        if let videoComposition {
            session.videoComposition = videoComposition
        }

        if !usePassthrough, quality == .medium {
            session.canPerformMultiplePassesOverSourceMediaData = true
        }

        if !usePassthrough, originalBytes > 0 {
            let factor = quality.targetSizeFactor(for: effectiveCodec, sourceIsHEVC: primarySub == kCMVideoCodecType_HEVC)
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

    private static func makeFPSCapVideoComposition(
        compositionVideoTrack: AVAssetTrack,
        sourceVideoTrack: AVAssetTrack,
        duration: CMTime,
        cappedFPS: Int
    ) async throws -> AVMutableVideoComposition {
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)

        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
        let transform = try await sourceVideoTrack.load(.preferredTransform)
        layer.setTransform(transform, at: .zero)
        instruction.layerInstructions = [layer]

        let naturalSize = try await sourceVideoTrack.load(.naturalSize)
        let rot = naturalSize.applying(transform)

        let vc = AVMutableVideoComposition()
        vc.instructions = [instruction]
        vc.renderSize = CGSize(width: abs(rot.width), height: abs(rot.height))
        vc.frameDuration = CMTime(value: 1, timescale: CMTimeScale(clamping: cappedFPS))
        return vc
    }

    private static func sourceIsHDR(track: AVAssetTrack, formatDescriptions: [CMFormatDescription]) async -> Bool {
        if let characteristics = try? await track.load(.mediaCharacteristics),
           characteristics.contains(.containsHDRVideo) {
            return true
        }
        for desc in formatDescriptions {
            if let ext = CMFormatDescriptionGetExtension(desc, extensionKey: kCMFormatDescriptionExtension_TransferFunction) as? String {
                let hlg = kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String
                let pq = kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String
                if ext == hlg || ext == pq { return true }
            }
        }
        return false
    }

    private static func exportWithProgress(
        session: AVAssetExportSession,
        outputURL: URL,
        progressHandler: (@Sendable (Float) -> Void)?
    ) async throws {
        let sessionBox = AVExportSessionBox(session)
        if let progressHandler {
            let monitor = Task {
                for await state in sessionBox.session.states(updateInterval: 0.1) {
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
            try await sessionBox.session.export(to: outputURL, as: .mp4)
            progressHandler(1)
        } else {
            try await sessionBox.session.export(to: outputURL, as: .mp4)
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

        if !sourceMatchesTarget {
            // HEVC → H.264: judge the source as the H.264 bitrate it would take to match it.
            guard isHEVC, codec == .h264, estimatedRate > 0 else { return false }
            return Double(estimatedRate) * VideoQuality.hevcToH264BitrateRatio < quality.skipIfEstimatedBitrateBelow
        }

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

private final class AVExportSessionBox: @unchecked Sendable {
    let session: AVAssetExportSession
    init(_ session: AVAssetExportSession) { self.session = session }
}

public enum VideoCompressionError: LocalizedError, Sendable {
    case exportSessionUnavailable
    case exportFailed(String)
    case alreadyOptimized

    public var errorDescription: String? {
        switch self {
        case .exportSessionUnavailable: return "Could not create export session for this video."
        case .exportFailed(let msg): return "Video export failed: \(msg)"
        case .alreadyOptimized: return "Video is already about as small as it’ll get for this setting."
        }
    }
}

extension VideoQuality {
    /// One-tier bump (`.high` is the ceiling).
    var bumpedUp: VideoQuality {
        switch self {
        case .medium: return .high
        case .high: return .high
        }
    }
}
