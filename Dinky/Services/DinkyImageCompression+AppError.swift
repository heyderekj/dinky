import DinkyCoreImage
import Foundation

extension DinkyImageCompressionError {
    /// Maps image pipeline errors to the app’s shared ``CompressionError`` for the UI and Shortcuts.
    func asAppError() -> CompressionError {
        switch self {
        case .binaryNotFound(let s):     return .binaryNotFound(s)
        case .processFailed(let c, let e): return .processFailed(c, e)
        case .outputMissing:            return .outputMissing
        case .heicTranscodeFailed:      return .heicTranscodeFailed
        case .heicEncodeFailed:         return .heicEncodeFailed
        case .imageResizeFailed:         return .imageResizeFailed
        case .imageReadFailed:          return .imageReadFailed
        case .imageWriteFailed:         return .imageWriteFailed
        }
    }
}
