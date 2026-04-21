import UniformTypeIdentifiers

enum CompressionFormat: String, CaseIterable, Identifiable, Codable {
    case webp = "webp"
    case avif = "avif"
    case png  = "png"
    case heic = "heic"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .webp: return S.webp
        case .avif: return S.avif
        case .png:  return S.png
        case .heic: return S.heic
        }
    }

    var outputExtension: String {
        switch self {
        case .webp: return "webp"
        case .avif: return "avif"
        case .png:  return "png"
        case .heic: return "heic"
        }
    }

    var binaryName: String {
        switch self {
        case .webp: return "cwebp"
        case .avif: return "avifenc"
        case .png:  return "oxipng"
        case .heic: return "imageio"
        }
    }

    var acceptedInputTypes: [UTType] {
        switch self {
        case .webp: return [.jpeg, .png, .webP, .tiff, .heic, .heif, .gif]
        case .avif: return [.jpeg, .png, .tiff, .heic, .heif]
        case .png:  return [.png, .heic, .heif]
        case .heic: return [.jpeg, .png, .webP, .tiff, .heic, .heif]
        }
    }
}
