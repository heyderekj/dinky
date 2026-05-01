// ContentClassifier.swift — multi-signal photo vs. graphic detection.
// (Same logic as the Dinky app; used by the macOS app and DinkyCoreImage CLI.)
import CoreGraphics
import Foundation
import ImageIO
import Vision

public enum ContentType: String, Sendable, Codable {
    case photo
    case graphic
    case mixed

    public var label: String {
        switch self {
        case .photo:   return "photo"
        case .graphic: return "graphic"
        case .mixed:   return "mixed"
        }
    }

    public var tooltipLabel: String {
        switch self {
        case .photo:   return "Detected as a photo — compressed more aggressively"
        case .graphic: return "Detected as a graphic (screenshot, UI, illustration, or logo) — quality preserved to keep edges crisp"
        case .mixed:   return "Mixed content — balanced compression applied"
        }
    }
}

public enum ContentClassifier {
    public static func classify(_ url: URL) -> ContentType {
        if let metaSignal = classifyFromMetadata(url: url) {
            return metaSignal
        }

        guard let cg = makeThumbnail(url: url, maxPixel: 320) else { return .mixed }

        let stats = sample(cgImage: cg)
        if let stats {
            if stats.uniqueColors > 10_000, stats.flatRatio < 0.10 {
                return .photo
            }
        }

        let textCoverage = detectTextCoverage(cgImage: cg)
        if textCoverage > 0.18 {
            return .graphic
        }

        if let stats {
            let (uniqueColors, flatRatio) = stats

            if uniqueColors < 1_200, flatRatio > 0.30 {
                return .graphic
            }
            if textCoverage > 0.08, flatRatio > 0.20 {
                return .graphic
            }
        }

        return .mixed
    }

    // MARK: - EXIF / TIFF

    private static func classifyFromMetadata(url: URL) -> ContentType? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any]
        else { return nil }

        let exif = props[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        let tiff = props[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]

        let software = (tiff["Software"] as? String ?? "").lowercased()
        if software.contains("screenshot") || software == "screencapture" {
            return .graphic
        }

        let hasCameraBrand = (tiff["Make"] as? String)?.isEmpty == false
            && (tiff["Model"] as? String)?.isEmpty == false
        let hasExposure = exif["FNumber"] != nil
            || exif["ExposureTime"] != nil
            || exif["ISOSpeedRatings"] != nil
            || exif["FocalLength"] != nil
        if hasCameraBrand && hasExposure {
            return .photo
        }

        if exif["LensModel"] != nil || exif["LensMake"] != nil {
            return .photo
        }

        return nil
    }

    // MARK: - Vision

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

        var coverage = 0.0
        for obs in observations {
            let box = obs.boundingBox
            coverage += Double(box.width * box.height)
        }
        return min(1.0, coverage)
    }

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

    /// Reused by video frame classification in the Dinky app.
    public static func samplePixelStats(_ cgImage: CGImage) -> (uniqueColors: Int, flatRatio: Double)? {
        sample(cgImage: cgImage)
    }

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
