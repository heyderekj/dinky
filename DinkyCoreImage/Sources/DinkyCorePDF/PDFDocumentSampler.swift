import AppKit
import DinkyCoreShared
import CoreGraphics
import Foundation
import PDFKit

/// Shared PDF page sampling for Smart Quality flatten, preserve heuristics, and mono detection.
public enum PDFDocumentSampler: Sendable {
    public static func sample(url: URL) -> PDFDocumentSignals? {
        guard let document = PDFDocument(url: url) else { return nil }
        let pageCount = document.pageCount
        guard pageCount > 0 else { return nil }

        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) } ?? 0
        let bytesPerPage = Double(fileSize) / Double(pageCount)

        let indices = samplePageIndices(pageCount: pageCount)
        var spreads: [Double] = []
        var fills: [Double] = []
        var textChars = 0

        for i in indices {
            guard let page = document.page(at: i) else { continue }
            if let stats = thumbnailStats(for: page) {
                spreads.append(stats.avgChromaSpread)
                fills.append(stats.nonWhiteFraction)
            }
            textChars += page.string?.count ?? 0
        }

        guard !spreads.isEmpty else { return nil }

        let avgSpread = spreads.reduce(0, +) / Double(spreads.count)
        let avgFill = fills.reduce(0, +) / Double(fills.count)

        return PDFDocumentSignals(
            pageCount: pageCount,
            bytesPerPage: bytesPerPage,
            avgChromaSpread: avgSpread,
            avgNonWhiteFill: avgFill,
            totalTextCharsSampled: textChars
        )
    }

    public static func samplePageIndices(pageCount: Int) -> [Int] {
        let cap = 5
        if pageCount <= cap {
            return Array(0..<pageCount)
        }
        var set = Set<Int>()
        set.insert(0)
        set.insert(pageCount - 1)
        set.insert(pageCount / 2)
        set.insert(pageCount / 4)
        set.insert((3 * pageCount) / 4)
        return Array(set).sorted()
    }

    struct ThumbStats {
        let avgChromaSpread: Double
        let nonWhiteFraction: Double
    }

    static func thumbnailStats(for page: PDFPage) -> ThumbStats? {
        let size = PDFPageRaster.displaySize(of: page)
        guard size.width > 1, size.height > 1 else { return nil }

        let maxEdge: CGFloat = 256
        let scale = min(maxEdge / size.width, maxEdge / size.height, 4)
        let pixelWidth = max(1, Int(size.width * scale))
        let pixelHeight = max(1, Int(size.height * scale))

        guard let ctx = PDFPageRaster.render(page, pixelWidth: pixelWidth, pixelHeight: pixelHeight,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }

        guard let data = ctx.data else { return nil }
        let count = pixelWidth * pixelHeight
        let ptr = data.bindMemory(to: UInt8.self, capacity: count * 4)

        var sumSpread = 0.0
        var nonWhite = 0
        let step = 4
        var samples = 0

        for i in stride(from: 0, to: count, by: step) {
            let o = i * 4
            let r = Double(ptr[o]) / 255
            let g = Double(ptr[o + 1]) / 255
            let b = Double(ptr[o + 2]) / 255
            let mx = max(r, g, b)
            let mn = min(r, g, b)
            sumSpread += mx - mn
            if r + g + b < 2.55 {
                nonWhite += 1
            }
            samples += 1
        }

        guard samples > 0 else { return nil }
        let avgSpread = sumSpread / Double(samples)
        let fill = Double(nonWhite) / Double(samples)
        return ThumbStats(avgChromaSpread: avgSpread, nonWhiteFraction: fill)
    }
}
