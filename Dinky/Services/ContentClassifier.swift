// ContentClassifier.swift — multi-signal photo vs. UI/screenshot detection.
// Drives Smart Quality: photos compress harder, UI screenshots keep more
// quality so text stays crisp.
//
// Signals, in order of confidence:
//   1. EXIF/TIFF metadata (camera make/model, FNumber, ExposureTime) → photo
//   2. Screenshot metadata hints (macOS / iOS screenshots add specific keys) → UI
//   3. Pixel sample on thumbnail — strong photo (many colors, low flatness) → photo (skip Vision)
//   4. Vision text-rect detection — >18% text coverage → UI
//   5. Pixel heuristics (unique-color count + flat-region ratio) → fallback
//
// All signals use Apple frameworks only (ImageIO, Vision, CoreGraphics).
// No SPM/CocoaPods dependencies. Dinky stays dinky.

import Foundation
import CoreGraphics
import ImageIO
import Vision

enum ContentType: String {
    case photo
    case ui
    case mixed

    /// Short label for the results chip.
    var label: String {
        switch self {
        case .photo: return "photo"
        case .ui:    return "UI"
        case .mixed: return "mixed"
        }
    }

    var tooltipLabel: String {
        switch self {
        case .photo: return "Detected as a photo — compressed more aggressively"
        case .ui:    return "Detected as a screenshot or UI — quality preserved to keep text crisp"
        case .mixed: return "Mixed content — balanced compression applied"
        }
    }
}

enum ContentClassifier {

    /// Classify a local image by URL. Returns `.mixed` when we can't read it
    /// (keeps default quality behavior). Runs fast — typically under 20 ms
    /// including the Vision pass, since we classify from a small thumbnail.
    static func classify(_ url: URL) -> ContentType {
        // Signal 1: EXIF/TIFF metadata. Strongest and cheapest — no decode needed.
        if let metaSignal = classifyFromMetadata(url: url) {
            return metaSignal
        }

        // Need a thumbnail for the remaining signals.
        guard let cg = makeThumbnail(url: url, maxPixel: 384) else { return .mixed }

        let stats = sample(cgImage: cg)
        if let stats {
            // Strong photo signal: lots of unique colors + barely any flat regions — skip Vision.
            if stats.uniqueColors > 10_000, stats.flatRatio < 0.10 {
                return .photo
            }
        }

        // Vision text detection. UI/screenshots almost always carry a significant text region.
        let textCoverage = detectTextCoverage(cgImage: cg)
        if textCoverage > 0.18 {
            return .ui
        }

        if let stats {
            let (uniqueColors, flatRatio) = stats

            // Strong UI signal: few colors + large flat regions.
            if uniqueColors < 1_200, flatRatio > 0.30 {
                return .ui
            }
            // Weak UI: some text-ish regions even without Vision hit.
            if textCoverage > 0.08, flatRatio > 0.20 {
                return .ui
            }
        }

        return .mixed
    }

    // MARK: - Signal 1: EXIF / TIFF metadata

    private static func classifyFromMetadata(url: URL) -> ContentType? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any]
        else { return nil }

        let exif = props[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        let tiff = props[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]

        // Screenshot hints: macOS and iOS tag screenshots with specific
        // Software fields ("Screenshot" / "Preview") or they carry almost
        // no camera metadata while still having a Make. We trust Software
        // strings — they're a loud, clean signal.
        let software = (tiff["Software"] as? String ?? "").lowercased()
        if software.contains("screenshot") || software == "screencapture" {
            return .ui
        }

        // Strong photo signal: genuine camera EXIF. The FNumber/ExposureTime
        // pair is only written by real cameras (or apps that mimic one —
        // which means the picture is photographic in intent either way).
        let hasCameraBrand = (tiff["Make"] as? String)?.isEmpty == false
                           && (tiff["Model"] as? String)?.isEmpty == false
        let hasExposure = exif["FNumber"] != nil
                        || exif["ExposureTime"] != nil
                        || exif["ISOSpeedRatings"] != nil
                        || exif["FocalLength"] != nil
        if hasCameraBrand && hasExposure {
            return .photo
        }

        // Lens info alone is also a solid photo tell.
        if exif["LensModel"] != nil || exif["LensMake"] != nil {
            return .photo
        }

        return nil   // inconclusive — continue to pixel signals
    }

    // MARK: - Signal 2: Vision text detection

    private static func detectTextCoverage(cgImage: CGImage) -> Double {
        let request = VNDetectTextRectanglesRequest()
        request.reportCharacterBoxes = false
        request.preferBackgroundProcessing = false
        request.revision = VNDetectTextRectanglesRequestRevision1

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return 0
        }
        guard let observations = request.results, !observations.isEmpty else { return 0 }

        // boundingBox is in normalized [0,1] coords — sum of areas is the coverage.
        // Two regions overlapping count twice, which is fine for a rough signal.
        var coverage = 0.0
        for obs in observations {
            let box = obs.boundingBox
            coverage += Double(box.width * box.height)
        }
        return min(1.0, coverage)
    }

    // MARK: - Thumbnail

    private static func makeThumbnail(url: URL, maxPixel: Int) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform:   true,
            kCGImageSourceThumbnailMaxPixelSize:          maxPixel,
            kCGImageSourceShouldCacheImmediately:         true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }

    // MARK: - Signal 3: pixel heuristics

    /// Draw the thumbnail into an RGBA buffer and compute:
    /// - unique color count across the whole buffer (quantized to 5 bits/ch)
    /// - flat-region ratio: fraction of 16x16 tiles where ≤3 unique colors appear
    private static func sample(cgImage: CGImage) -> (uniqueColors: Int, flatRatio: Double)? {
        let width  = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return nil }

        let bytesPerPixel = 4
        let bytesPerRow   = width * bytesPerPixel
        let capacity      = height * bytesPerRow

        var buffer = [UInt8](repeating: 0, count: capacity)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
                       | CGBitmapInfo.byteOrder32Big.rawValue

        guard let ctx = buffer.withUnsafeMutableBytes({ rawPtr -> CGContext? in
            guard let base = rawPtr.baseAddress else { return nil }
            return CGContext(data: base,
                             width: width,
                             height: height,
                             bitsPerComponent: 8,
                             bytesPerRow: bytesPerRow,
                             space: colorSpace,
                             bitmapInfo: bitmapInfo)
        }) else { return nil }

        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var seen = Set<UInt32>()
        seen.reserveCapacity(2048)
        buffer.withUnsafeBufferPointer { ptr in
            let pixelCount = width * height
            for i in 0..<pixelCount {
                let off = i * 4
                let r = UInt32(ptr[off]     >> 3)
                let g = UInt32(ptr[off + 1] >> 3)
                let b = UInt32(ptr[off + 2] >> 3)
                seen.insert((r << 10) | (g << 5) | b)
            }
        }

        let tile = 16
        var flatTiles = 0
        var totalTiles = 0
        var tileSeen = Set<UInt32>()
        tileSeen.reserveCapacity(64)

        buffer.withUnsafeBufferPointer { ptr in
            var y = 0
            while y < height {
                var x = 0
                while x < width {
                    tileSeen.removeAll(keepingCapacity: true)
                    let yMax = min(y + tile, height)
                    let xMax = min(x + tile, width)
                    for ty in y..<yMax {
                        let rowOffset = ty * bytesPerRow
                        for tx in x..<xMax {
                            let off = rowOffset + tx * 4
                            let r = UInt32(ptr[off]     >> 3)
                            let g = UInt32(ptr[off + 1] >> 3)
                            let b = UInt32(ptr[off + 2] >> 3)
                            tileSeen.insert((r << 10) | (g << 5) | b)
                            if tileSeen.count > 3 { break }
                        }
                        if tileSeen.count > 3 { break }
                    }
                    if tileSeen.count <= 3 { flatTiles += 1 }
                    totalTiles += 1
                    x += tile
                }
                y += tile
            }
        }

        let flatRatio = totalTiles > 0 ? Double(flatTiles) / Double(totalTiles) : 0
        return (seen.count, flatRatio)
    }
}
