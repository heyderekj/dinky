import Foundation

/// Threshold on ``PDFDocumentSignals/scanLikelihood`` to treat a document as scan-like for OCR.
public enum PDFScanDetection {
    public static let ocrLikelihoodThreshold: Double = 0.42
}

/// Cheap signals from a quick PDF sample (same page indices as flatten Smart Quality).
public struct PDFDocumentSignals: Sendable {
    public let pageCount: Int
    public let bytesPerPage: Double
    public let avgChromaSpread: Double
    public let avgNonWhiteFill: Double
    /// Sum of `PDFPage.string` lengths on sampled pages (text density hint).
    public let totalTextCharsSampled: Int

    public init(
        pageCount: Int,
        bytesPerPage: Double,
        avgChromaSpread: Double,
        avgNonWhiteFill: Double,
        totalTextCharsSampled: Int
    ) {
        self.pageCount = pageCount
        self.bytesPerPage = bytesPerPage
        self.avgChromaSpread = avgChromaSpread
        self.avgNonWhiteFill = avgNonWhiteFill
        self.totalTextCharsSampled = totalTextCharsSampled
    }

    /// 0...1 — image-heavy / low extractable text vs born-digital text; includes color scans (not just mono).
    public var scanLikelihood: Double {
        guard pageCount > 0 else { return 0 }
        let sampled = min(5, pageCount)
        let avgChars = Double(totalTextCharsSampled) / Double(max(1, sampled))
        if avgChars > 120 { return 0 }
        if avgChars > 50 { return 0.08 }
        let bpp = bytesPerPage
        if bpp < 12_000 { return min(0.15, 1.0 - avgChars / 80.0) }
        if bpp > 4_000_000 { return 0.22 }
        let textEmpty = min(1.0, 1.0 - avgChars / 45.0)
        let densityCue = min(1.0, (bpp - 12_000) / 1_100_000)
        let colorBoost = avgChromaSpread > 0.02 ? 0.22 : 0.05
        let monoBoost = monochromeScanLikelihood >= 0.35 ? 0.18 : 0
        return min(1.0, textEmpty * (0.42 + 0.48 * densityCue) + colorBoost + monoBoost)
    }

    /// 0...1 — likely office / fax-style monochrome scan (flatten path may auto-grayscale).
    public var monochromeScanLikelihood: Double {
        guard pageCount > 0 else { return 0 }
        // Typical camera scans and color docs have meaningful chroma; B&W text scans do not.
        if avgChromaSpread > 0.022 { return 0 }
        let bpp = bytesPerPage
        if bpp < 35_000 || bpp > 1_200_000 { return 0 }
        // Heavy ink coverage or very empty pages — both common in scans.
        let extremeFill = avgNonWhiteFill < 0.06 || avgNonWhiteFill > 0.88
        if extremeFill { return min(1, 0.55 + (0.022 - avgChromaSpread) * 12) }
        if avgNonWhiteFill < 0.12, avgChromaSpread < 0.015 { return 0.45 }
        return 0
    }
}
