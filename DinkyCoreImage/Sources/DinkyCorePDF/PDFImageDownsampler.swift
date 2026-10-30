import AppKit
import CoreGraphics
import Foundation
import ImageIO
import PDFKit

/// Mixed-mode PDF: rasterizes image-heavy pages at 144 DPI while keeping text pages from a structure-preserved source.
public enum PDFImageDownsampler: Sendable {
    private static let imagePageTextThreshold = 500
    private static let rasterDPI: CGFloat = 144
    private static let jpegQuality: CGFloat = 0.72

    public static func downsample(source: URL, structureDoc: PDFDocument, stripMetadata: Bool) -> PDFDocument? {
        guard let sourceDoc = PDFDocument(url: source) else { return nil }
        let pageCount = sourceDoc.pageCount
        guard pageCount > 0, structureDoc.pageCount == pageCount else { return nil }

        let output = PDFDocument()
        var rasterizedCount = 0

        for i in 0..<pageCount {
            guard let sourcePage = sourceDoc.page(at: i) else { continue }
            let textChars = sourcePage.string?.count ?? 0

            if textChars < imagePageTextThreshold, let rasterPage = rasterize(page: sourcePage) {
                output.insert(rasterPage, at: output.pageCount)
                rasterizedCount += 1
            } else if let structPage = structureDoc.page(at: i) {
                output.insert(structPage, at: output.pageCount)
            }
        }

        guard rasterizedCount > 0 else { return nil }
        if !stripMetadata, let attrs = sourceDoc.documentAttributes {
            var safeAttrs = attrs
            safeAttrs.removeValue(forKey: PDFDocumentAttribute.authorAttribute)
            safeAttrs.removeValue(forKey: PDFDocumentAttribute.creatorAttribute)
            output.documentAttributes = safeAttrs
        }
        return output
    }

    private static func rasterize(page: PDFPage) -> PDFPage? {
        let size = PDFPageRaster.displaySize(of: page)
        guard size.width > 1, size.height > 1 else { return nil }

        let scale = rasterDPI / 72.0
        let pixelWidth = max(1, Int((size.width * scale).rounded(.down)))
        let pixelHeight = max(1, Int((size.height * scale).rounded(.down)))

        guard let ctx = PDFPageRaster.render(page, pixelWidth: pixelWidth, pixelHeight: pixelHeight),
              let cgImage = ctx.makeImage(),
              let jpeg = PDFPageRaster.jpegData(cgImage, quality: jpegQuality) else { return nil }
        return PDFPageRaster.imagePage(jpeg: jpeg, size: size)
    }
}
