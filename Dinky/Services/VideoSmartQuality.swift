import Foundation
import AVFoundation

/// Heuristic video export tier from track metadata + content type.
enum VideoSmartQuality {

    /// What we picked + why. Surfaced in `CompressionResult` so the UI can show a chip.
    struct Decision: Sendable {
        let quality: VideoQuality
        let contentType: VideoContentType
        /// True when the source carries HDR (HLG / PQ / Dolby Vision). The compressor uses this to
        /// force an HDR-preserving HEVC preset even if the user picked H.264.
        let isHDR: Bool
    }

    /// Picks a ``VideoQuality`` from resolution, estimated bitrate, and content type.
    /// On failure, returns `fallback` with `.generic` content type and `isHDR == false`.
    static func decide(source: URL, fallback: VideoQuality) async -> Decision {
        await decide(asset: VideoCompressor.makeURLAsset(url: source), fallback: fallback)
    }

    /// Same as ``decide(source:fallback:)`` but reuses a loaded ``AVURLAsset`` (avoids a second file open).
    static func decide(asset: AVURLAsset, fallback: VideoQuality) async -> Decision {
        let contentType = await VideoContentClassifier.classify(asset: asset)
        let isHDR = await detectHDR(asset: asset)

        do {
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let track = tracks.first else {
                return Decision(quality: fallback, contentType: contentType, isHDR: isHDR)
            }

            let size = try await track.load(.naturalSize)
            let rate = try await track.load(.estimatedDataRate)
            let transform = try await track.load(.preferredTransform)
            let transformed = size.applying(transform)
            let w = abs(transformed.width)
            let h = abs(transformed.height)
            guard w >= 1, h >= 1 else {
                return Decision(quality: fallback, contentType: contentType, isHDR: isHDR)
            }

            let maxDim = Double(max(w, h))
            let minDim = Double(min(w, h))
            let megapixels = (w * h) / 1_000_000.0

            var quality = mapSignals(
                maxDimension: maxDim, minDimension: minDim,
                megapixels: megapixels, bitsPerSecond: rate
            )

            // Content-aware adjustment: screen recordings AND animation / motion graphics get
            // bumped up one tier so text and sub-pixel edges stay readable. The resolution /
            // bitrate ladder is calibrated for film-style footage and tends to under-encode
            // edge-heavy / flat-region content at the `.medium` tier.
            if contentType == .screenRecording || contentType == .animation {
                quality = quality.bumpedUp
            }

            return Decision(quality: quality, contentType: contentType, isHDR: isHDR)
        } catch {
            return Decision(quality: fallback, contentType: contentType, isHDR: isHDR)
        }
    }

    /// Convenience wrapper for callers that only need the tier.
    static func inferQuality(asset: AVURLAsset, fallback: VideoQuality) async -> VideoQuality {
        await decide(asset: asset, fallback: fallback).quality
    }

    static func inferQuality(source: URL, fallback: VideoQuality) async -> VideoQuality {
        await decide(source: source, fallback: fallback).quality
    }

    // MARK: - HDR

    /// Cheap HDR check via `.containsHDRVideo`. Falls back to inspecting the video format
    /// description's transfer function (HLG / PQ) for older / unusual files.
    private static func detectHDR(asset: AVAsset) async -> Bool {
        do {
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let track = tracks.first else { return false }

            let characteristics = try await track.load(.mediaCharacteristics)
            if characteristics.contains(.containsHDRVideo) { return true }

            let descriptions = try await track.load(.formatDescriptions)
            for desc in descriptions {
                if let ext = CMFormatDescriptionGetExtension(desc, extensionKey: kCMFormatDescriptionExtension_TransferFunction) as? String {
                    let hlg = kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String
                    let pq  = kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String
                    if ext == hlg || ext == pq { return true }
                }
            }
        } catch {
            return false
        }
        return false
    }

    private static func mapSignals(
        maxDimension: Double,
        minDimension: Double,
        megapixels: Double,
        bitsPerSecond: Float
    ) -> VideoQuality {
        let rate = Double(bitsPerSecond)

        // `.medium` is the floor — `.low` was removed because it produced unacceptable artifacts
        // for a quality-first compressor. Tiny sub-540p clips therefore default to `.medium`,
        // which is still aggressive on size but keeps text and faces legible.
        if maxDimension < 540 || megapixels < 0.22 {
            return .medium
        }

        if maxDimension <= 960 || megapixels < 0.65 {
            return rate > 10_000_000 ? .high : .medium
        }

        if maxDimension <= 1440 {
            if rate > 14_000_000 { return .high }
            return .medium
        }

        if maxDimension <= 1920 {
            if minDimension >= 1080, rate > 12_000_000 { return .high }
            return .medium
        }

        return .high
    }
}

private extension VideoQuality {
    /// One-tier bump (`.high` is the ceiling).
    var bumpedUp: VideoQuality {
        switch self {
        case .medium: return .high
        case .high:   return .high
        }
    }
}
