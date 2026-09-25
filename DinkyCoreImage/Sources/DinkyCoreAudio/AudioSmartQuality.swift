import AVFoundation
import DinkyCoreShared
import Foundation
import os

/// Picks AAC tier (and occasionally nudges toward a better tier) from track bit rate metadata.
public enum AudioSmartQuality: Sendable {

    private static let log = Logger(subsystem: "dinky", category: "AudioSmartQuality")

    public struct Decision: Sendable {
        public let format: AudioConversionFormat
        public let tier: AudioConversionQualityTier

        public init(format: AudioConversionFormat, tier: AudioConversionQualityTier) {
            self.format = format
            self.tier = tier
        }
    }

    public static func decide(
        asset: AVURLAsset,
        userFormat: AudioConversionFormat,
        userTier: AudioConversionQualityTier
    ) async -> Decision {
        let t0 = CFAbsoluteTimeGetCurrent()
        defer {
            log.debug(
                "audio.smartQuality.decide \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - t0))s"
            )
        }

        do {
            let tracks = try await asset.loadTracks(withMediaType: .audio)
            guard let track = tracks.first else {
                return Decision(format: userFormat, tier: userTier)
            }
            let rate = try await track.load(.estimatedDataRate)
            let formatID = await sourceFormatID(track)
            return decide(
                sourceBitsPerSecond: Double(rate),
                sourceIsLossless: formatID.map(losslessFormatIDs.contains),
                userFormat: userFormat,
                userTier: userTier
            )
        } catch {
            return Decision(format: userFormat, tier: userTier)
        }
    }

    /// Codecs that store audio without loss; anything else (AAC, MP3, Opus…) is already lossy.
    static let losslessFormatIDs: Set<AudioFormatID> = [
        kAudioFormatLinearPCM, kAudioFormatAppleLossless, kAudioFormatFLAC,
    ]

    /// - Parameter sourceIsLossless: nil when the codec couldn't be read.
    public static func decide(
        sourceBitsPerSecond bps: Double,
        sourceIsLossless: Bool?,
        userFormat: AudioConversionFormat,
        userTier: AudioConversionQualityTier
    ) -> Decision {
        guard bps > 0 else { return Decision(format: userFormat, tier: userTier) }

        if sourceIsLossless == false {
            // Already lossy (a typical 256–320 kbps MP3/AAC). Re-encoding to a lossless format only
            // inflates it, and a tier at or above the source's bitrate can't make it smaller — both
            // made ordinary music files come out bigger and get discarded as "no gain".
            let format: AudioConversionFormat = userFormat.isLossless ? .aacM4A : userFormat
            let fits = [AudioConversionQualityTier.archival, .balanced, .smallest].first {
                Double(targetBitrate(format: format, tier: $0)) <= bps * 0.8
            } ?? .smallest
            // Never above what the user asked for.
            return Decision(format: format, tier: rank(fits) < rank(userTier) ? fits : userTier)
        }

        var tier = userTier

        // Already very compressed — avoid over-shrinking speech / low-bit podcasts.
        if bps < 88_000, userTier == .smallest {
            tier = .balanced
        }

        // High-bitrate masters — bump toward archival lossy tier (or stay lossless-bound).
        if bps >= 230_000 {
            tier = .archival
        } else if bps >= 180_000, tier == .smallest {
            tier = .balanced
        }

        var format = userFormat
        // Archival + lossy AAC → prefer FLAC for mastering / web delivery of lossless sources.
        if tier == .archival, format == .aacM4A, sourceIsLossless == true {
            format = .flac
        }

        return Decision(format: format, tier: tier)
    }

    private static func rank(_ tier: AudioConversionQualityTier) -> Int {
        switch tier {
        case .smallest: return 0
        case .balanced: return 1
        case .archival: return 2
        }
    }

    private static func targetBitrate(format: AudioConversionFormat, tier: AudioConversionQualityTier) -> Int {
        format == .mp3 ? tier.lameCBRBitrateKbps * 1000 : tier.aacTotalBitrateBps
    }

    private static func sourceFormatID(_ track: AVAssetTrack) async -> AudioFormatID? {
        guard let fd = try? await track.load(.formatDescriptions).first,
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fd)
        else { return nil }
        return asbd.pointee.mFormatID
    }
}
