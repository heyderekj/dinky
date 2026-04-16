import Foundation
import SwiftUI

enum CompressionStatus {
    case pending
    case processing
    case done(outputURL: URL, originalSize: Int64, outputSize: Int64)
    case skipped                 // already optimized
    case zeroGain(original: URL) // compressed ≥ original
    case failed(Error)

    var isTerminal: Bool {
        switch self {
        case .pending, .processing: return false
        default: return true
        }
    }
}

@MainActor
final class ImageItem: ObservableObject, Identifiable {
    let id = UUID()
    let sourceURL: URL
    var formatOverride: CompressionFormat? = nil

    @Published var status: CompressionStatus = .pending
    @Published var detectedContentType: ContentType? = nil

    init(sourceURL: URL) {
        self.sourceURL = sourceURL
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
