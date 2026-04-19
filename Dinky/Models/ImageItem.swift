import Foundation
import SwiftUI
import PDFKit

enum CompressionStatus {
    case pending
    case processing
    case done(outputURL: URL, originalSize: Int64, outputSize: Int64)
    /// Compressed below the user's threshold. `savedPercent` is `nil` when the
    /// encoder bailed early (e.g. video `alreadyOptimized`) without a number.
    case skipped(savedPercent: Double?, threshold: Int)
    /// Compressed ≥ original. `attemptedSize` is what the encoder produced
    /// before we discarded it — used to show "would have been X MB" in the
    /// detail sheet.
    case zeroGain(attemptedSize: Int64)
    case failed(Error)

    var isTerminal: Bool {
        switch self {
        case .pending, .processing: return false
        default: return true
        }
    }
}

@MainActor
final class CompressionItem: ObservableObject, Identifiable {
    let id = UUID()
    let sourceURL: URL
    let mediaType: MediaType
    var formatOverride: CompressionFormat? = nil

    @Published var status: CompressionStatus = .pending
    @Published var detectedContentType: ContentType? = nil
    /// Smart Quality result for videos. `nil` for non-videos or when Smart Quality is off.
    @Published var detectedVideoContentType: VideoContentType? = nil
    /// True when the source carried HDR (HLG / PQ / Dolby Vision) and the export preserved it.
    @Published var videoIsHDR: Bool = false

    var forceCompress: Bool = false
    var pageCount: Int? = nil
    var videoDuration: Double? = nil
    /// When set, compression uses this preset’s stored options (`CompressionPreset`) instead of the sidebar.
    var presetID: UUID? = nil

    /// One-shot flatten-PDF quality from the results list context menu; skips smart inference when set.
    var pdfQualityOverride: PDFQuality? = nil
    /// One-shot video quality + codec from the context menu; skips smart inference when set.
    var videoRecompressOverride: (quality: VideoQuality, codec: VideoCodecFamily)? = nil

    /// `0...1` while `AVAssetExportSession` is running; `nil` otherwise.
    @Published var videoExportProgress: Double? = nil

    init(sourceURL: URL, presetID: UUID? = nil) {
        self.sourceURL = sourceURL
        self.presetID = presetID
        self.mediaType = MediaTypeDetector.detect(sourceURL) ?? .image
        if self.mediaType == .pdf {
            self.pageCount = PDFDocument(url: sourceURL)?.pageCount
        }
    }

    var filename: String { sourceURL.lastPathComponent }

    var originalSize: Int64 {
        (try? sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { Int64($0) } ?? 0
    }

    var savedBytes: Int64 {
        guard case .done(_, let orig, let out) = status else { return 0 }
        return max(0, orig - out)
    }

    var savedPercent: Double {
        guard case .done(_, let orig, let out) = status, orig > 0 else { return 0 }
        return Double(orig - out) / Double(orig) * 100
    }

    var outputURL: URL? {
        if case .done(let url, _, _) = status { return url }
        return nil
    }

    var statusLabel: String {
        switch status {
        case .pending:               return "Waiting"
        case .processing:            return "Processing…"
        case .done:                  return String(format: "%.1f%% smaller", savedPercent)
        case .skipped:               return S.skipped
        case .zeroGain:              return S.zeroBytes
        case .failed:                return S.errored
        }
    }
}

// Keep ImageItem as a typealias so any code not yet updated still compiles.
typealias ImageItem = CompressionItem
