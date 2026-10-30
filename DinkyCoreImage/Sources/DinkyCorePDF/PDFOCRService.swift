import AppKit
import CoreGraphics
import CoreText
import DinkyCoreShared
import Foundation
import PDFKit
import Vision

/// Adds a searchable (invisible) text layer to scanned-style PDF pages using Vision OCR.
public enum PDFOCRService: Sendable {
    private static let renderDPI: CGFloat = 200

    /// Writes a new PDF with invisible text overlaid on rasterized page content.
    public static func makeSearchableCopy(
        sourceURL: URL,
        outputURL: URL,
        languages: [String],
        progressHandler: @escaping @Sendable (Int, Int) -> Void
    ) async throws {
        guard let doc = PDFDocument(url: sourceURL), doc.pageCount > 0 else {
            throw PDFOCRError.cannotOpenSource
        }
        let total = doc.pageCount
        let langs = languages.isEmpty ? CompressionPreset.defaultPdfOCRLanguages : languages
        let maxConcurrent = maxConcurrentPageTasks(pageCount: total)

        struct PagePayload: Sendable {
            let index: Int
            let pdfData: Data
        }

        var payloads: [PagePayload] = []
        for start in stride(from: 0, to: total, by: maxConcurrent) {
            let end = min(start + maxConcurrent, total)
            try await withThrowingTaskGroup(of: PagePayload.self) { group in
                for idx in start..<end {
                    let url = sourceURL
                    let langList = langs
                    group.addTask {
                        guard let d = PDFDocument(url: url), let page = d.page(at: idx) else {
                            throw PDFOCRError.cannotOpenSource
                        }
                        let data = try Self.pdfDataForPage(page: page, languages: langList)
                        return PagePayload(index: idx, pdfData: data)
                    }
                }
                for try await p in group {
                    payloads.append(p)
                }
            }
            progressHandler(end, total)
        }
        payloads.sort { $0.index < $1.index }

        let out = PDFDocument()
        for p in payloads {
            guard let onePageDoc = PDFDocument(data: p.pdfData), let page = onePageDoc.page(at: 0) else {
                throw PDFOCRError.pageBuildFailed
            }
            out.insert(page, at: out.pageCount)
        }

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard out.write(to: outputURL) else {
            throw PDFOCRError.writeFailed
        }
    }

    private static func maxConcurrentPageTasks(pageCount: Int) -> Int {
        let cpu = max(1, ProcessInfo.processInfo.activeProcessorCount)
        let ramBytes = ProcessInfo.processInfo.physicalMemory
        let memCap = max(1, min(cpu, Int(ramBytes / (512 * 1024 * 1024))))
        return max(1, min(pageCount, memCap))
    }

    private static func pdfDataForPage(page: PDFPage, languages: [String]) throws -> Data {
        guard let cgImage = renderPageImage(page: page) else {
            throw PDFOCRError.renderFailed
        }
        let observations = try recognizeText(cgImage: cgImage, languages: languages)
        let mediaBox = CGRect(origin: .zero, size: PDFPageRaster.displaySize(of: page))
        return try buildSinglePagePDF(mediaBox: mediaBox, cgImage: cgImage, observations: observations)
    }

    private static func renderPageImage(page: PDFPage) -> CGImage? {
        let size = PDFPageRaster.displaySize(of: page)
        guard size.width > 1, size.height > 1 else { return nil }
        let scale = renderDPI / 72.0
        let pixelWidth = max(1, Int(size.width * scale))
        let pixelHeight = max(1, Int(size.height * scale))

        return PDFPageRaster.render(page, pixelWidth: pixelWidth, pixelHeight: pixelHeight,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
    }

    private static func recognizeText(cgImage: CGImage, languages: [String]) throws -> [VNRecognizedTextObservation] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = languages

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])
        return request.results ?? []
    }

    private static func buildSinglePagePDF(
        mediaBox: CGRect,
        cgImage: CGImage,
        observations: [VNRecognizedTextObservation]
    ) throws -> Data {
        let data = NSMutableData()
        var box = mediaBox
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else {
            throw PDFOCRError.pageBuildFailed
        }

        ctx.beginPDFPage(nil)
        ctx.saveGState()
        ctx.translateBy(x: 0, y: mediaBox.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: mediaBox.width, height: mediaBox.height))
        ctx.restoreGState()

        ctx.saveGState()
        for obs in observations {
            guard let cand = obs.topCandidates(1).first else { continue }
            let s = cand.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !s.isEmpty else { continue }
            let n = obs.boundingBox
            let rect = CGRect(
                x: mediaBox.minX + n.minX * mediaBox.width,
                y: mediaBox.minY + n.minY * mediaBox.height,
                width: n.width * mediaBox.width,
                height: n.height * mediaBox.height
            )
            drawInvisibleText(s, in: rect, context: ctx)
        }
        ctx.restoreGState()

        ctx.endPDFPage()
        ctx.closePDF()
        return data as Data
    }

    private static func drawInvisibleText(_ text: String, in rect: CGRect, context ctx: CGContext) {
        guard rect.width > 0.5, rect.height > 0.5 else { return }
        let fontSize = max(3, min(rect.height * 0.85, 48))
        let font = NSFont.systemFont(ofSize: fontSize)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.alignment = .left
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraph,
        ]
        let attributed = NSAttributedString(string: text, attributes: attrs)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let path = CGPath(rect: rect, transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: attributed.length), path, nil)
        ctx.saveGState()
        ctx.setTextDrawingMode(.invisible)
        CTFrameDraw(frame, ctx)
        ctx.restoreGState()
    }
}

public enum PDFOCRError: LocalizedError, Sendable {
    case cannotOpenSource
    case renderFailed
    case pageBuildFailed
    case writeFailed

    public var errorDescription: String? {
        switch self {
        case .cannotOpenSource: return "Could not open the PDF for OCR."
        case .renderFailed: return "Could not render a PDF page for OCR."
        case .pageBuildFailed: return "Could not build an OCR PDF page."
        case .writeFailed: return "Could not write the OCR PDF."
        }
    }
}
