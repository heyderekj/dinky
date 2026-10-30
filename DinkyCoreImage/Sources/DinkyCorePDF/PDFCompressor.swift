import AppKit
import CoreGraphics
import DinkyCoreShared
import Foundation
import ImageIO
import PDFKit

/// How PDFs are written: keep structure (text, links, forms) or rasterize pages for maximum shrink.
public enum PDFOutputMode: String, CaseIterable, Identifiable, Sendable, Codable {
    case preserveStructure = "preserveStructure"
    case flattenPages = "flattenPages"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .preserveStructure:
            return String(localized: "Preserve text (best-effort size)", comment: "PDF output mode short label.")
        case .flattenPages:
            return String(localized: "Smallest file (flatten pages)", comment: "PDF output mode short label.")
        }
    }

    public var shortDescription: String {
        switch self {
        case .preserveStructure:
            return String(localized: "qpdf + PDFKit when smaller; keeps text and links. Many PDFs won’t shrink.", comment: "PDF preserve mode description.")
        case .flattenPages:
            return String(localized: "Rasterizes each page to JPEG for reliable smaller files. No selectable text or links.", comment: "PDF flatten mode description.")
        }
    }
}

public enum PDFQuality: String, CaseIterable, Identifiable, Sendable, Codable {
    case smallest = "smallest"
    case low = "low"
    case medium = "medium"
    case high = "high"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .smallest: return String(localized: "Smallest", comment: "PDF flatten quality tier.")
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }

    public var dpi: CGFloat {
        switch self {
        case .smallest: return 72
        case .low: return 88
        case .medium: return 120
        case .high: return 160
        }
    }

    public var jpegQuality: CGFloat {
        switch self {
        case .smallest: return 0.26
        case .low: return 0.34
        case .medium: return 0.48
        case .high: return 0.64
        }
    }

    public var description: String {
        switch self {
        case .smallest: return String(localized: "Minimum size. 72 DPI — screen sharing and quick previews only.", comment: "PDF flatten quality tier description.")
        case .low: return String(localized: "Very small. ~88 DPI — fine for screen viewing.", comment: "PDF flatten quality tier description.")
        case .medium: return String(localized: "Balanced. ~120 DPI — good for most purposes.", comment: "PDF flatten quality tier description.")
        case .high: return String(localized: "Sharper. ~160 DPI — better for print than Medium.", comment: "PDF flatten quality tier description.")
        }
    }

    private static let flattenTierDescending: [PDFQuality] = [.high, .medium, .low, .smallest]

    public static func flattenQualityFallbackChain(startingAt first: PDFQuality) -> [PDFQuality] {
        guard let i = flattenTierDescending.firstIndex(of: first) else { return [first] }
        return Array(flattenTierDescending[i...])
    }
}

public enum PDFCompressor: Sendable {
    private static let flattenMaxRasterEdgePixels = 5632
    private static let flattenLastResortMaxRasterEdgePixels = 4096
    private static let flattenUltraMaxRasterEdgePixels = 2048

    private static func resourceByteCount(_ url: URL) -> Int64 {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) } ?? 0
    }

    public static func preserveStructure(
        source: URL,
        stripMetadata: Bool,
        outputURL: URL,
        collisionSourceURL: URL,
        collisionNamingStyle: CollisionNamingStyle,
        collisionCustomPattern: String,
        progress: (@Sendable (Float) -> Void)? = nil
    ) throws -> URL {
        progress?(0.12)
        guard let document = PDFDocument(url: source) else {
            throw PDFCompressionError.loadFailed
        }
        guard document.pageCount > 0 else { throw PDFCompressionError.noPages }

        progress?(0.55)
        if stripMetadata {
            document.documentAttributes = nil
        } else if let attrs = document.documentAttributes {
            var safeAttrs = attrs
            safeAttrs.removeValue(forKey: PDFDocumentAttribute.authorAttribute)
            safeAttrs.removeValue(forKey: PDFDocumentAttribute.creatorAttribute)
            document.documentAttributes = safeAttrs
        }

        progress?(0.82)
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("dinky_pdf_preserve_\(UUID().uuidString).pdf")
        guard document.write(to: tmp) else {
            throw PDFCompressionError.writeFailed
        }
        let srcBytes = resourceByteCount(source)
        let dstBytes = resourceByteCount(tmp)
        if dstBytes < srcBytes {
            let out = try OutputPathUniqueness.moveTempItemToUniqueOutput(
                temp: tmp,
                desiredOutput: outputURL,
                sourceURL: collisionSourceURL,
                style: collisionNamingStyle,
                customPattern: collisionCustomPattern
            )
            progress?(1)
            return out
        } else {
            try? FileManager.default.removeItem(at: tmp)
            throw PDFCompressionError.rewriteNotSmallerThanOriginal(attemptedSize: dstBytes)
        }
    }

    public static func compressFlattened(
        source: URL,
        quality: PDFQuality,
        grayscale: Bool,
        stripMetadata: Bool,
        outputURL: URL,
        lastResortFlatten: Bool = false,
        ultraLastResortFlatten: Bool = false,
        progress: (@Sendable (Float) -> Void)? = nil
    ) throws {
        progress?(0.06)
        guard let document = PDFDocument(url: source) else {
            throw PDFCompressionError.loadFailed
        }

        let pageCount = document.pageCount
        guard pageCount > 0 else { throw PDFCompressionError.noPages }

        let flattenDpi: CGFloat
        let flattenJpegQ: CGFloat
        let maxEdgePx: CGFloat
        if ultraLastResortFlatten {
            flattenDpi = 36
            flattenJpegQ = 0.17
            maxEdgePx = CGFloat(flattenUltraMaxRasterEdgePixels)
        } else if lastResortFlatten {
            flattenDpi = 48
            flattenJpegQ = 0.23
            maxEdgePx = CGFloat(flattenLastResortMaxRasterEdgePixels)
        } else {
            flattenDpi = quality.dpi
            flattenJpegQ = quality.jpegQuality
            maxEdgePx = CGFloat(flattenMaxRasterEdgePixels)
        }

        progress?(0.1)
        let output = PDFDocument()

        for i in 0..<pageCount {
            guard let page = document.page(at: i) else { continue }
            let size = PDFPageRaster.displaySize(of: page)
            guard size.width > 0, size.height > 0 else { continue }

            let baseScale = flattenDpi / 72.0
            var rasterW = size.width * baseScale
            var rasterH = size.height * baseScale
            let longEdge = max(rasterW, rasterH)
            if longEdge > maxEdgePx {
                let factor = maxEdgePx / longEdge
                rasterW *= factor
                rasterH *= factor
            }
            let pixelWidth = max(1, Int(rasterW.rounded(.down)))
            let pixelHeight = max(1, Int(rasterH.rounded(.down)))

            guard let ctx = PDFPageRaster.render(page, pixelWidth: pixelWidth, pixelHeight: pixelHeight, grayscale: grayscale) else {
                throw PDFCompressionError.renderFailed(i)
            }
            guard let cgImage = ctx.makeImage(),
                  let jpeg = PDFPageRaster.jpegData(cgImage, quality: flattenJpegQ),
                  let renderedPage = PDFPageRaster.imagePage(jpeg: jpeg, size: size) else { continue }
            output.insert(renderedPage, at: output.pageCount)
            progress?(0.1 + 0.78 * Float(i + 1) / Float(pageCount))
        }

        if stripMetadata {
        } else {
            if let attrs = document.documentAttributes {
                var safeAttrs = attrs
                safeAttrs.removeValue(forKey: PDFDocumentAttribute.authorAttribute)
                safeAttrs.removeValue(forKey: PDFDocumentAttribute.creatorAttribute)
                output.documentAttributes = safeAttrs
            }
        }

        progress?(0.92)
        guard output.write(to: outputURL) else {
            throw PDFCompressionError.writeFailed
        }
        progress?(1)
    }
}

public enum PDFCompressionError: LocalizedError, Sendable {
    case loadFailed
    case noPages
    case renderFailed(Int)
    case writeFailed
    case rewriteNotSmallerThanOriginal(attemptedSize: Int64)

    public var errorDescription: String? {
        switch self {
        case .loadFailed: return "Could not open the PDF file."
        case .noPages: return "The PDF has no pages."
        case .renderFailed(let p): return "Could not render page \(p + 1)."
        case .writeFailed: return "Could not write the compressed PDF."
        case .rewriteNotSmallerThanOriginal:
            return String(localized: "Saving the PDF did not reduce its size compared to the original.", comment: "PDF preserve: rewrite was larger or the same size.")
        }
    }
}
