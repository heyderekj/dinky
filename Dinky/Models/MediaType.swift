import UniformTypeIdentifiers

enum MediaType: Equatable {
    case image
    case pdf
    case video
}

/// Which file types a preset applies to (stored on ``CompressionPreset``).
enum PresetMediaScope: String, CaseIterable, Identifiable {
    case all
    case image
    case video
    case pdf

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: return "All"
        case .image: return "Images"
        case .pdf: return "PDFs"
        case .video: return "Videos"
        }
    }
}

enum MediaTypeDetector {
    private static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "avif", "tiff", "bmp"]
    private static let videoExtensions: Set<String> = ["mp4", "mov", "m4v"]

    static func detect(_ url: URL) -> MediaType? {
        let ext = url.pathExtension.lowercased()
        if imageExtensions.contains(ext) { return .image }
        if ext == "pdf" { return .pdf }
        if videoExtensions.contains(ext) { return .video }
        guard let uti = UTType(filenameExtension: ext) else { return nil }
        if uti.conforms(to: .movie) || uti.conforms(to: .video) { return .video }
        if uti.conforms(to: .pdf) { return .pdf }
        if uti.conforms(to: .image) { return .image }
        return nil
    }
}
