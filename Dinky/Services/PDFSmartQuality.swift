import Foundation
import DinkyPDFSignals
import PDFKit
import CoreGraphics
import AppKit

/// Heuristic PDF flatten quality tier from quick page sampling (runs off the main thread).
enum PDFSmartQuality {

    /// Picks a ``PDFQuality`` from document structure and rendered thumbnails. On any failure, returns `fallback`.
    static func inferQuality(url: URL, fallback: PDFQuality) -> PDFQuality {
        guard let s = PDFDocumentSampler.sample(url: url) else { return fallback }
        return inferQualityFromSignals(s, fallback: fallback)
    }

    /// Single sample pass: flatten tier + monochrome likelihood (for auto-grayscale and tier bias).
    static func inferFlattenQualityAndMono(
        url: URL,
        fallback: PDFQuality,
        autoGrayscaleMonoScans: Bool
    ) -> (quality: PDFQuality, monoLikelihood: Double) {
        guard let s = PDFDocumentSampler.sample(url: url) else {
            return (fallback, 0)
        }
        var q = inferQualityFromSignals(s, fallback: fallback)
        let mono = s.monochromeScanLikelihood
        if autoGrayscaleMonoScans && mono >= 0.5 {
            q = stepOneTierSmaller(q)
        }
        return (q, mono)
    }

    private static func stepOneTierSmaller(_ q: PDFQuality) -> PDFQuality {
        switch q {
        case .high: return .medium
        case .medium: return .low
        case .low: return .smallest
        case .smallest: return .smallest
        }
    }

    private static func inferQualityFromSignals(_ s: PDFDocumentSignals, fallback: PDFQuality) -> PDFQuality {
        let bytesPerPage = s.bytesPerPage
        let avgSpread = s.avgChromaSpread
        let avgFill = s.avgNonWhiteFill

        if bytesPerPage >= 85_000, bytesPerPage < 560_000 {
            if avgSpread > 0.065 || avgFill > 0.11 {
                return .smallest
            }
            if avgSpread > 0.045 {
                return .low
            }
        }

        return mapSignals(bytesPerPage: bytesPerPage, avgChromaSpread: avgSpread, avgNonWhiteFill: avgFill)
    }

    private static func mapSignals(bytesPerPage: Double, avgChromaSpread: Double, avgNonWhiteFill: Double) -> PDFQuality {
        if bytesPerPage < 260_000 {
            if avgChromaSpread < 0.035, avgNonWhiteFill < 0.07 {
                return .smallest
            }
            if avgChromaSpread < 0.055, avgNonWhiteFill < 0.12 {
                return .low
            }
            return .low
        }
        if bytesPerPage > 520_000 {
            if avgChromaSpread > 0.14 || avgNonWhiteFill > 0.32 {
                return .low
            }
            return .smallest
        }
        if bytesPerPage > 2_300_000, avgChromaSpread > 0.10 || avgNonWhiteFill > 0.25 {
            return .high
        }
        if bytesPerPage > 1_350_000, avgChromaSpread > 0.115, avgNonWhiteFill > 0.27 {
            return .high
        }
        if bytesPerPage > 880_000, avgNonWhiteFill > 0.20, avgChromaSpread > 0.09 {
            return .high
        }
        if avgChromaSpread > 0.11, avgNonWhiteFill > 0.28 {
            return bytesPerPage > 240_000 ? .low : .medium
        }
        if bytesPerPage > 380_000, avgNonWhiteFill > 0.14 {
            return .low
        }
        if avgChromaSpread < 0.035, avgNonWhiteFill < 0.07, bytesPerPage < 95_000 {
            return .smallest
        }
        if avgChromaSpread < 0.045, avgNonWhiteFill < 0.11, bytesPerPage < 180_000 {
            return .low
        }
        return .low
    }
}
