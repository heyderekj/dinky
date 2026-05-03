import Foundation

/// Output container/codec for audio conversion (not to be confused with image ``CompressionFormat``).
public enum AudioConversionFormat: String, CaseIterable, Codable, Sendable, Identifiable {
    case aacM4A = "aac_m4a"
    case alacM4A = "alac_m4a"
    case wav = "wav"
    case aiff = "aiff"
    case flac = "flac"
    case mp3 = "mp3"

    public var id: String { rawValue }

    public var fileExtension: String {
        switch self {
        case .aacM4A, .alacM4A: return "m4a"
        case .wav: return "wav"
        case .aiff: return "aiff"
        case .flac: return "flac"
        case .mp3: return "mp3"
        }
    }

    public var displayName: String {
        switch self {
        case .aacM4A: return "AAC (M4A)"
        case .alacM4A: return "Apple Lossless (M4A)"
        case .wav: return "WAV"
        case .aiff: return "AIFF"
        case .flac: return "FLAC"
        case .mp3: return "MP3"
        }
    }

    /// Abbreviated label for chip grids where horizontal space is tight.
    public var chipLabel: String {
        switch self {
        case .aacM4A:  return "AAC"
        case .alacM4A: return "Lossless"
        case .wav:     return "WAV"
        case .aiff:    return "AIFF"
        case .flac:    return "FLAC"
        case .mp3:     return "MP3"
        }
    }

    /// Short helper copy shown under audio format chips.
    public var description: String {
        switch self {
        case .aacM4A:
            return "Great default: compact files and wide playback support."
        case .alacM4A:
            return "Lossless quality in an Apple-friendly container."
        case .wav:
            return "Uncompressed PCM audio; largest files, universally compatible."
        case .aiff:
            return "Uncompressed audio like WAV, common in Apple/pro workflows."
        case .flac:
            return "Lossless compression with much smaller files than WAV/AIFF."
        case .mp3:
            return "Legacy lossy format with broad device and browser support."
        }
    }
}

/// User-facing quality intent for lossy codecs (AAC / MP3). Lossless targets ignore tier bitrates.
public enum AudioConversionQualityTier: String, CaseIterable, Codable, Sendable, Identifiable {
    /// Smallest reasonable file (speech / background music).
    case smallest = "smallest"
    /// Default “good” tradeoff — web playback, AirPods, etc.
    case balanced = "balanced"
    /// High fidelity lossy — or triggers lossless picks in Smart Quality.
    case archival = "archival"

    public var id: String { rawValue }

    public static func resolve(_ raw: String) -> AudioConversionQualityTier {
        AudioConversionQualityTier(rawValue: raw) ?? .balanced
    }

    /// Total bitrate for AAC (bps) passing to `afconvert -b`.
    public var aacTotalBitrateBps: Int {
        switch self {
        case .smallest: return 96_000
        case .balanced: return 128_000
        case .archival: return 256_000
        }
    }

    /// CBR bitrate for LAME `-b`.
    public var lameCBRBitrateKbps: Int {
        switch self {
        case .smallest: return 128
        case .balanced: return 192
        case .archival: return 320
        }
    }

    public var displayName: String {
        switch self {
        case .smallest: return String(localized: "Smallest", comment: "Audio quality tier.")
        case .balanced: return String(localized: "Balanced", comment: "Audio quality tier.")
        case .archival: return String(localized: "High", comment: "Audio quality tier (archival/high fidelity lossy).")
        }
    }
}
