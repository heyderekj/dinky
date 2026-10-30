import AppKit
import CoreGraphics
import Foundation
import ImageIO
import PDFKit

/// Rasterizing a page the way viewers show it: the crop box, with `/Rotate` applied, so the
/// output page keeps the original's size and orientation.
enum PDFPageRaster {
    /// Size of the visible page in points: the crop box (PDFKit falls back to the media box),
    /// with width and height swapped for pages rotated a quarter turn.
    static func displaySize(of page: PDFPage) -> CGSize {
        let box = page.bounds(for: .cropBox)
        let quarterTurn = abs(page.rotation / 90) % 2 == 1
        return quarterTurn ? CGSize(width: box.height, height: box.width) : box.size
    }

    /// Draws the visible page into a `pixelWidth` × `pixelHeight` bitmap on white.
    static func render(
        _ page: PDFPage,
        pixelWidth: Int,
        pixelHeight: Int,
        grayscale: Bool = false,
        bitmapInfo: UInt32? = nil
    ) -> CGContext? {
        let size = displaySize(of: page)
        guard size.width > 0, size.height > 0 else { return nil }
        let colorSpace = grayscale ? CGColorSpaceCreateDeviceGray() : CGColorSpaceCreateDeviceRGB()
        let info = bitmapInfo ?? (grayscale ? CGImageAlphaInfo.none.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue)
        guard let ctx = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: info
        ) else { return nil }

        ctx.setFillColor(grayscale ? CGColor(gray: 1, alpha: 1) : CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        ctx.scaleBy(x: CGFloat(pixelWidth) / size.width, y: CGFloat(pixelHeight) / size.height)

        // `draw(with:to:)` moves the box origin to zero and applies the page's rotation.
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        page.draw(with: .cropBox, to: ctx)
        NSGraphicsContext.current = nil
        NSGraphicsContext.restoreGraphicsState()
        return ctx
    }

    static func jpegData(_ image: CGImage, quality: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, [
            kCGImageDestinationLossyCompressionQuality: quality,
            kCGImageDestinationOptimizeColorForSharing: true,
            kCGImagePropertyJFIFIsProgressive: true,
        ] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    /// A one-page PDF exactly `size` points, filled by the JPEG. Quartz embeds the JPEG
    /// bytes as-is (DCTDecode), so nothing is re-encoded.
    static func imagePage(jpeg: Data, size: CGSize) -> PDFPage? {
        guard let provider = CGDataProvider(data: jpeg as CFData),
              let image = CGImage(jpegDataProviderSource: provider, decode: nil,
                                  shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        let pdfData = NSMutableData()
        var box = CGRect(origin: .zero, size: size)
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { return nil }
        ctx.beginPDFPage(nil)
        ctx.draw(image, in: box)
        ctx.endPDFPage()
        ctx.closePDF()
        return PDFDocument(data: pdfData as Data)?.page(at: 0)
    }
}
