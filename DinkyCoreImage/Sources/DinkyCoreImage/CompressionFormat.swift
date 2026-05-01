import Foundation
import UniformTypeIdentifiers

public enum CompressionFormat: String, CaseIterable, Identifiable, Codable, Sendable {
    case webp = "webp"
    case avif = "avif"
    case png  = "png"
    case heic = "heic"

    public var id: String { rawValue }

    public var outputExtension: String {
        switch self {
        case .webp: return "webp"
        case .avif: return "avif"
        case .png:  return "png"
        case .heic: return "heic"
        }
    }

    public var binaryName: String {
        switch self {
        case .webp: return "cwebp"
        case .avif: return "avifenc"
        case .png:  return "oxipng"
        case .heic: return "imageio"
        }
    }

    public var acceptedInputTypes: [UTType] {
        switch self {
        case .webp: return [.jpeg, .png, .webP, .tiff, .heic, .heif, .gif]
        case .avif: return [.jpeg, .png, .tiff, .heic, .heif]
        case .png:  return [.png, .heic, .heif]
        case .heic: return [.jpeg, .png, .webP, .tiff, .heic, .heif]
        }
    }
}
