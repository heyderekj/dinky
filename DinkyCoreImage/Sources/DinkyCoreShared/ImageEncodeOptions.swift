import Foundation

/// AVIF chroma subsampling override. `auto` follows Smart Quality content type (photo→420, graphic→444, mixed→422).
public enum ChromaSubsampling: String, CaseIterable, Identifiable, Codable, Sendable {
    case auto
    case yuv420
    case yuv422
    case yuv444

    public var id: String { rawValue }

    public var avifYUVFlag: String? {
        switch self {
        case .auto:   return nil
        case .yuv420: return "420"
        case .yuv422: return "422"
        case .yuv444: return "444"
        }
    }

    public var displayName: String {
        switch self {
        case .auto:   return "Auto"
        case .yuv420: return "4:2:0"
        case .yuv422: return "4:2:2"
        case .yuv444: return "4:4:4"
        }
    }

    public var description: String {
        switch self {
        case .auto:
            return "Smart Quality picks subsampling from content type."
        case .yuv420:
            return "Smallest files; color detail is reduced (typical for photos)."
        case .yuv422:
            return "Balanced chroma — between photo and graphic defaults."
        case .yuv444:
            return "Full color resolution — best for text, UI, and sharp edges."
        }
    }
}

/// PNG output strategy. `optimized` tries indexed PNG-8 when the image has ≤256 opaque colors.
public enum PNGOutputMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case lossless
    case optimized

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .lossless:  return "Lossless"
        case .optimized: return "Optimized"
        }
    }

    public var description: String {
        switch self {
        case .lossless:
            return "Full-color PNG, then oxipng (current behavior)."
        case .optimized:
            return "Uses a palette when colors fit in 256 slots; otherwise full-color lossless."
        }
    }
}
