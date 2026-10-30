import AppKit
import DinkyCoreShared
import CoreGraphics
import Foundation
import PDFKit

/// Heuristic PDF flatten quality tier from quick page sampling (runs off the main thread).
public enum PDFSmartQuality: Sendable {
    public static func inferQuality(url: URL, fallback: PDFQuality) -> PDFQuality {
        guard let s = PDFDocumentSampler.sample(url: url) else { return fallback }
        return textFloor(inferQualityFromSignals(s, fallback: fallback), s)
    }

    public static func inferFlattenQualityAndMono(
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
        return (textFloor(q, s), mono)
    }

    /// Real text turns to mush below ~120 DPI, so born-digital text pages never go under Medium.
    private static func textFloor(_ q: PDFQuality, _ s: PDFDocumentSignals) -> PDFQuality {
        guard s.scanLikelihood == 0 else { return q }
        return q == .smallest || q == .low ? .medium : q
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
