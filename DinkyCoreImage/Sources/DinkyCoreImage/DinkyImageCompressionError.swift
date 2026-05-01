import Foundation

public enum DinkyImageCompressionError: LocalizedError, Sendable {
    case binaryNotFound(String)
    case processFailed(Int32, String)
    case outputMissing
    case heicTranscodeFailed
    case heicEncodeFailed
    case imageResizeFailed
    case imageReadFailed
    case imageWriteFailed

    public var errorDescription: String? {
        switch self {
        case .binaryNotFound(let n):
            return "Binary '\(n)' not found in Dinky’s encoder path."
        case .processFailed(let c, let e):
            return "Process exited \(c): \(e)"
        case .outputMissing:
            return "Output file was not created."
        case .heicTranscodeFailed:
            return "Could not read or convert this HEIC/HEIF image."
        case .heicEncodeFailed:
            return "Could not encode this image as HEIC."
        case .imageResizeFailed:
            return "Could not resize this image for the width limit."
        case .imageReadFailed:
            return "Could not read image data from this file."
        case .imageWriteFailed:
            return "Could not write the compressed image file."
        }
    }
}
