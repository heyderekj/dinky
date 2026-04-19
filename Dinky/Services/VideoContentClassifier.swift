// VideoContentClassifier.swift — content-aware video classification.
// Mirrors `ContentClassifier` for images. Used by Smart Quality to nudge the
// export tier per content type (e.g. screen recordings and motion graphics get
// bumped up so text and edges stay crisp).
//
// Signals, in order of confidence:
//   1. QuickTime / common metadata `software` → screen recording when it
//      contains "screen" / "screencapture" / "loom" / "obs" / "screenflow".
//   2. Camera `make` / `model` → real camera footage (iPhone, Sony, Canon…).
//   3. 3-frame pixel sample (only when metadata is inconclusive) → animation /
//      motion graphics when the frames look graphic-y (few colors + flat regions).
//      Reuses ``ContentClassifier.samplePixelStats`` so video and image
//      classification share one heuristic.
//   4. Otherwise → generic.
//
// All Apple frameworks. No SPM/CocoaPods. Dinky stays dinky.

import Foundation
import AVFoundation
import CoreGraphics

enum VideoContentType: String {
    case screenRecording
    case camera
    /// 2D animation, motion graphics, vector exports — sharp edges + flat regions.
    /// Compresses like a screen recording (text and edges matter), so it gets the
    /// same one-tier bump in Smart Quality.
    case animation
    case generic

    /// Short label for the results chip.
    var label: String {
        switch self {
        case .screenRecording: return "screen"
        case .camera:          return "camera"
        case .animation:       return "animation"
        case .generic:         return "video"
        }
    }

    var tooltipLabel: String {
        switch self {
        case .screenRecording:
            return "Detected as a screen recording — quality nudged up so text stays crisp"
        case .camera:
            return "Detected as camera footage — compressed at the standard tier for the source"
        case .animation:
            return "Detected as animation / motion graphics — quality nudged up so edges stay crisp"
        case .generic:
            return "Generic video — compressed at the standard tier for the source"
        }
    }
}

enum VideoContentClassifier {

    static func classify(asset: AVAsset) async -> VideoContentType {
        // Common + QuickTime metadata — both are cheap to load.
        let common: [AVMetadataItem]
        do {
            common = try await asset.load(.commonMetadata)
        } catch {
            common = []
        }

        if let software = await stringValue(in: common, identifier: .commonIdentifierSoftware),
           looksLikeScreenRecording(software) {
            return .screenRecording
        }

        // QuickTime-specific: "com.apple.quicktime.software" — most macOS
        // screen recordings tag themselves here even when the common key is empty.
        let qtMeta: [AVMetadataItem]
        do {
            qtMeta = try await asset.loadMetadata(for: .quickTimeMetadata)
        } catch {
            qtMeta = []
        }

        if let qtSoftware = await stringValue(in: qtMeta, identifier: .quickTimeMetadataSoftware),
           looksLikeScreenRecording(qtSoftware) {
            return .screenRecording
        }

        // Camera signal: make + model present (and not a screen recording).
        let make: String?
        if let m = await stringValue(in: common, identifier: .commonIdentifierMake) {
            make = m
        } else {
            make = await stringValue(in: qtMeta, identifier: .quickTimeMetadataMake)
        }
        let model: String?
        if let m = await stringValue(in: common, identifier: .commonIdentifierModel) {
            model = m
        } else {
            model = await stringValue(in: qtMeta, identifier: .quickTimeMetadataModel)
        }
        if (make?.isEmpty == false) && (model?.isEmpty == false) {
            return .camera
        }

        // Metadata didn't tell us anything strong. Sample a few frames to look for the
        // animation / motion-graphic signature (flat fills + few unique colors). This is
        // the only path that decodes pixels — gated to inconclusive cases so latency stays
        // low for the common case (camera / screen recording / metadata-tagged).
        if await framesLookLikeAnimation(asset: asset) {
            return .animation
        }

        return .generic
    }

    // MARK: - Helpers

    private static func looksLikeScreenRecording(_ software: String) -> Bool {
        let s = software.lowercased()
        // macOS / iOS native screen capture, plus common third-party tools.
        return s.contains("screen")
            || s.contains("screencapture")
            || s.contains("quicktime")        // QuickTime Player screen recording exports
            || s.contains("loom")
            || s.contains("obs")
            || s.contains("screenflow")
            || s.contains("camtasia")
            || s.contains("cleanshot")
    }

    private static func stringValue(in items: [AVMetadataItem], identifier: AVMetadataIdentifier) async -> String? {
        let matched = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: identifier)
        for item in matched {
            if let s = try? await item.load(.stringValue), !s.isEmpty { return s }
        }
        return nil
    }

    // MARK: - Frame sampling (animation detection)

    /// Pulls 3 small thumbnails from the clip and asks ``ContentClassifier.samplePixelStats``
    /// whether they look graphic-y. Thresholds are slightly looser than the image classifier
    /// because video frames tend to have softer edges / more chroma noise from prior encoding.
    ///
    /// Returns `false` on any failure — we'd rather miss a few animations than mis-classify
    /// camera footage as animation and over-encode it.
    private static func framesLookLikeAnimation(asset: AVAsset) async -> Bool {
        let durationSeconds: Double
        do {
            durationSeconds = try await CMTimeGetSeconds(asset.load(.duration))
        } catch {
            return false
        }
        guard durationSeconds.isFinite, durationSeconds > 0 else { return false }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 256, height: 256)
        // We don't care about exact frame timing — accept any nearby frame for speed.
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter  = .positiveInfinity

        // Sample at 25 / 50 / 75 % to avoid title cards and end frames that may not
        // represent the body of the clip. Clamp very short clips to safe times.
        let fractions: [Double] = [0.25, 0.5, 0.75]
        let times = fractions.map { CMTime(seconds: max(0.05, durationSeconds * $0), preferredTimescale: 600) }

        var totalUnique = 0
        var totalFlat   = 0.0
        var samples     = 0

        for time in times {
            let cg: CGImage
            do {
                cg = try await generator.image(at: time).image
            } catch {
                continue
            }
            guard let stats = ContentClassifier.samplePixelStats(cg) else { continue }
            totalUnique += stats.uniqueColors
            totalFlat   += stats.flatRatio
            samples     += 1
        }

        guard samples > 0 else { return false }
        let meanUnique = Double(totalUnique) / Double(samples)
        let meanFlat   = totalFlat / Double(samples)

        // Threshold rationale:
        // - meanUnique < 1500: live-action frames typically carry 5k–30k unique colors
        //   even at 256px. Animation / motion graphics sit well below that.
        // - meanFlat > 0.25: requires meaningful flat regions across multiple frames,
        //   which screen-record-style and animated content reliably show but live action does not.
        return meanUnique < 1500 && meanFlat > 0.25
    }
}
