import Foundation
import SwiftUI
import PDFKit

/// Captures enough state to reverse a successful compression (restore original, remove output).
struct CompressionUndoSnapshot: Equatable {
    var sourceURL: URL
    var outputURL: URL
    /// Trash or backup path where the original bytes were moved; `nil` if the original stayed at `sourceURL`.
    var originalRecoveryURL: URL?
    var replaceOriginal: Bool
    var isURLDownloadSource: Bool
}

enum CompressionStatus {
    case pending
    /// Direct media URL fetch in progress (`totalBytes` nil when length unknown).
    case downloading(progress: Double, bytesReceived: Int64, totalBytes: Int64?, displayHost: String)
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
        case .pending, .downloading, .processing: return false
        default: return true
        }
    }
}

@MainActor
final class CompressionItem: ObservableObject, Identifiable {
    let id = UUID()
    /// Local file URL (or temp path while a remote URL is still downloading).
    var sourceURL: URL
    var mediaType: MediaType
    var formatOverride: CompressionFormat? = nil

    @Published var status: CompressionStatus = .pending
    @Published var detectedContentType: ContentType? = nil
    /// Smart Quality result for videos. `nil` for non-videos or when Smart Quality is off.
    @Published var detectedVideoContentType: VideoContentType? = nil
    /// True when the source carried HDR (HLG / PQ / Dolby Vision) and the export preserved it.
    @Published var videoIsHDR: Bool = false
    /// True when a multi-frame source (e.g. GIF) was compressed using only the first frame.
    @Published var usedFirstFrameOnly: Bool = false
    /// Set when an image was downscaled to fit a width limit.
    @Published var imageResize: ImageResizeInfo? = nil

    var forceCompress: Bool = false
    @Published var pageCount: Int? = nil
    var videoDuration: Double? = nil
    /// When set, compression uses this preset’s stored options (`CompressionPreset`) instead of the sidebar.
    var presetID: UUID? = nil
    /// Arrived via a Watch folder (not drag-and-drop / Open / Services). Uses the Watch originals policy.
    var ingestedFromWatchFolder: Bool = false
    /// Size and modification date when added — tells a changed file from a repeat watch event.
    var sourceFingerprint: FileFingerprint? = nil
    /// True when the file was fetched from an `http(s)` URL (temp download). Affects output path and original disposal.
    var isURLDownloadSource: Bool = false
    /// While downloading, the original remote URL (for cancel / logging).
    var pendingRemoteURL: URL?
    /// Cancel an in-flight URL download.
    var downloadTask: Task<Void, Never>?

    /// One-shot flatten-PDF quality from the results list context menu; skips smart inference when set.
    var pdfQualityOverride: PDFQuality? = nil
    /// One-shot PDF output mode (e.g. zero-gain sheet “flatten smallest”); cleared when compression starts.
    var pdfOutputModeOverride: PDFOutputMode? = nil
    /// One-shot experimental qpdf options for preserve mode (zero-gain retry); cleared when compression starts.
    var pdfPreserveExperimentalOverride: PDFPreserveExperimentalMode? = nil
    /// One-shot video quality + codec from the context menu; skips smart inference when set.
    var videoRecompressOverride: (quality: VideoQuality, codec: VideoCodecFamily)? = nil

    /// `0...1` while compression is in progress (video export, staged image/PDF steps); `nil` when idle or indeterminate.
    @Published var compressionProgress: Double? = nil
    /// Optional sub-step label (e.g. OCR page progress); `nil` when not applicable.
    @Published var compressionStageLabel: String? = nil
    /// Last completed PDF job: user had “Make scanned PDFs searchable” on.
    var lastPdfCompressionOCROptIn: Bool = false
    /// Last completed PDF job: Vision OCR layer was written before compression.
    var lastPdfCompressionOCRApplied: Bool = false

    /// Set when compression succeeds; cleared after undo or re-queue.
    var undoSnapshot: CompressionUndoSnapshot?
    /// When `status` is `.zeroGain` for a PDF, which output mode produced the failed attempt (for sheet copy).
    var zeroGainPDFOutputMode: PDFOutputMode?

    init(sourceURL: URL, presetID: UUID? = nil, mediaType: MediaType? = nil) {
        self.sourceURL = sourceURL
        self.presetID = presetID
        self.undoSnapshot = nil
        self.mediaType = mediaType ?? (MediaTypeDetector.detect(sourceURL) ?? .image)
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
        case .downloading(let p, _, _, _):
            return p >= 0 ? String(format: "Downloading %.0f%%", p * 100) : "Downloading…"
        case .processing:            return "Processing…"
        case .done:
            if savedPercent <= 0, let resize = imageResize {
                return String.localizedStringWithFormat(
                    String(localized: "Resized to %lld px wide", comment: "Result status when an image was downscaled to the width limit but the file didn't get smaller. Argument is the new width in pixels."),
                    Int64(resize.outputWidth)
                )
            }
            return String(format: "%.1f%% smaller", savedPercent)
        case .skipped:               return S.skipped
        case .zeroGain:              return S.zeroBytes
        case .failed:                return S.errored
        }
    }
}

// Keep ImageItem as a typealias so any code not yet updated still compiles.
typealias ImageItem = CompressionItem
