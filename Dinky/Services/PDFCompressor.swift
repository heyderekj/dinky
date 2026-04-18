import Foundation
import AppKit
import PDFKit
import CoreGraphics
import ImageIO

/// How PDFs are written: keep structure (text, links, forms) or rasterize pages for maximum shrink.
enum PDFOutputMode: String, CaseIterable, Identifiable {
    case preserveStructure = "preserveStructure"
    case flattenPages = "flattenPages"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .preserveStructure: return "Preserve text and links"
        case .flattenPages:      return "Smallest size (flatten pages)"
        }
    }

    var shortDescription: String {
        switch self {
        case .preserveStructure:
            return "Keeps selectable text, links, and forms. Rewrites the file and strips metadata."
        case .flattenPages:
            return "Rasterizes pages to images for smaller files. No text selection or interactive links."
        }
    }
}

enum PDFQuality: String, CaseIterable, Identifiable {
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

    var dpi: CGFloat {
        switch self {
        case .low:    return 96
        case .medium: return 144
        case .high:   return 192
        }
    }

    var jpegQuality: CGFloat {
        switch self {
        case .low:    return 0.50
        case .medium: return 0.72
        case .high:   return 0.88
        }
    }

    var description: String {
        switch self {
        case .low:    return "Smallest file. 96 DPI — fine for screen viewing."
        case .medium: return "Balanced. 144 DPI — good for most purposes."
        case .high:   return "Near-lossless. 192 DPI — best for printing."
        }
    }
}

enum PDFCompressor {

    /// Rewrites the PDF without rasterizing: preserves text, annotations, links, and typical form structures.
    static func preserveStructure(source: URL, stripMetadata: Bool, outputURL: URL) throws {
        guard let document = PDFDocument(url: source) else {
            throw PDFCompressionError.loadFailed
        }
        guard document.pageCount > 0 else { throw PDFCompressionError.noPages }

        if stripMetadata {
            document.documentAttributes = nil
        } else if let attrs = document.documentAttributes {
            var safeAttrs = attrs
            safeAttrs.removeValue(forKey: PDFDocumentAttribute.authorAttribute)
            safeAttrs.removeValue(forKey: PDFDocumentAttribute.creatorAttribute)
            document.documentAttributes = safeAttrs
        }

        guard document.write(to: outputURL) else {
            throw PDFCompressionError.writeFailed
        }
    }

    /// Rasterizes each page to JPEG (legacy “compress” behavior).
    static func compressFlattened(
        source: URL,
        quality: PDFQuality,
        grayscale: Bool,
        stripMetadata: Bool,
        outputURL: URL
    ) throws {
        guard let document = PDFDocument(url: source) else {
            throw PDFCompressionError.loadFailed
        }

        let pageCount = document.pageCount
        guard pageCount > 0 else { throw PDFCompressionError.noPages }

        let output = PDFDocument()

        for i in 0..<pageCount {
            guard let page = document.page(at: i) else { continue }
            let bounds = page.bounds(for: .mediaBox)

            let scale = quality.dpi / 72.0
            let pixelWidth  = Int(bounds.width  * scale)
            let pixelHeight = Int(bounds.height * scale)

            guard pixelWidth > 0, pixelHeight > 0 else { continue }

            // Render page to bitmap (grayscale saves ~60% on B&W documents)
            let colorSpace = grayscale ? CGColorSpaceCreateDeviceGray() : CGColorSpaceCreateDeviceRGB()
            let bitmapInfo = grayscale
                ? CGImageAlphaInfo.none.rawValue
                : CGImageAlphaInfo.noneSkipLast.rawValue
            guard let ctx = CGContext(
                data: nil,
                width: pixelWidth,
                height: pixelHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else { throw PDFCompressionError.renderFailed(i) }

            ctx.setFillColor(grayscale ? CGColor(gray: 1, alpha: 1) : CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
            ctx.scaleBy(x: scale, y: scale)

            let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
            NSGraphicsContext.current = nsCtx
            page.draw(with: .mediaBox, to: ctx)
            NSGraphicsContext.current = nil

            guard let cgImage = ctx.makeImage() else { continue }

            // JPEG in memory — avoids disk + extra color-management roundtrip through `NSImage(contentsOf:)`.
            let jpegData = NSMutableData()
            guard let dest = CGImageDestinationCreateWithData(jpegData, "public.jpeg" as CFString, 1, nil) else {
                continue
            }
            let opts: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality.jpegQuality]
            CGImageDestinationAddImage(dest, cgImage, opts as CFDictionary)
            guard CGImageDestinationFinalize(dest) else { continue }

            guard let nsImage = NSImage(data: jpegData as Data),
                  let renderedPage = PDFPage(image: nsImage) else { continue }
            // Restore page bounds to original size (PDFPage from image defaults to pixel size at 72dpi)
            renderedPage.setBounds(bounds, for: .mediaBox)
            output.insert(renderedPage, at: output.pageCount)
        }

        if stripMetadata {
            // PDFDocument doesn't expose per-attribute stripping; we skip writing
            // the document attributes by not copying them to `output`.
        } else {
            // Copy non-identifying attributes (subject, keywords)
            if let attrs = document.documentAttributes {
                var safeAttrs = attrs
                safeAttrs.removeValue(forKey: PDFDocumentAttribute.authorAttribute)
                safeAttrs.removeValue(forKey: PDFDocumentAttribute.creatorAttribute)
                output.documentAttributes = safeAttrs
            }
        }

        guard output.write(to: outputURL) else {
            throw PDFCompressionError.writeFailed
        }
    }
}

enum PDFCompressionError: LocalizedError {
    case loadFailed
    case noPages
    case renderFailed(Int)
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .loadFailed:        return "Could not open the PDF file."
        case .noPages:           return "The PDF has no pages."
        case .renderFailed(let p): return "Could not render page \(p + 1)."
        case .writeFailed:       return "Could not write the compressed PDF."
        }
    }
}
