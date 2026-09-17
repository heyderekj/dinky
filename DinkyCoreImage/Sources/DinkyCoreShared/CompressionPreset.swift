import Foundation

public struct CompressionPreset: Codable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    // Format
    public var format: CompressionFormat
    public var smartQuality: Bool
    public var autoFormat: Bool
    // Limits
    public var maxWidthEnabled: Bool
    public var maxWidth: Int
    public var maxFileSizeEnabled: Bool
    public var maxFileSizeKB: Int
    // Output
    public var saveLocationRaw: String
    public var filenameHandlingRaw: String
    public var customSuffix: String
    /// Optional folder created inside the destination for this preset's results, e.g.
    /// `compressed-webp`. Empty means write straight into the destination.
    public var outputSubfolder: String

    /// Trims a user-typed subfolder name down to a single safe path component. Returns nil when
    /// nothing usable is left, so callers fall back to writing directly into the destination.
    public static func sanitizedOutputSubfolder(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // One level only: a typed "/" (or "..") must not let output escape the destination.
        let component = trimmed
            .components(separatedBy: CharacterSet(charactersIn: "/\\"))
            .first { !$0.isEmpty && $0 != "." && $0 != ".." }
        guard let component, !component.isEmpty else { return nil }
        return String(component.prefix(100))
    }
    public var collisionNamingStyleRaw: String
    public var collisionCustomPattern: String
    // Advanced
    public var stripMetadata: Bool
    public var sanitizeFilenames: Bool
    public var openFolderWhenDone: Bool
    // Notifications
    public var notifyWhenDone: Bool
    // Watch folder (per-preset)
    public var watchFolderEnabled: Bool
    public var watchFolderModeRaw: String
    public var watchFolderPath: String
    public var watchFolderBookmark: Data
    public var presetCustomFolderPath: String
    public var presetCustomFolderBookmark: Data
    public var contentTypeHintRaw: String
    /// ``ChromaSubsampling`` raw value for AVIF (`auto` default).
    public var chromaSubsamplingRaw: String
    /// When true, WebP output uses `cwebp -lossless` instead of lossy quality tiers.
    public var webpLossless: Bool
    /// ``PNGOutputMode`` raw value (`lossless` default).
    public var pngOutputModeRaw: String
    public var presetMediaScopeRaw: String
    public var pdfOutputModeRaw: String
    public var pdfQualityRaw: String
    public var videoQualityRaw: String
    public var videoCodecFamilyRaw: String
    public var pdfGrayscale: Bool
    public var pdfAutoGrayscaleMonoScans: Bool
    public var pdfPreserveExperimentalRaw: String
    public var pdfMaxFileSizeEnabled: Bool
    public var pdfMaxFileSizeKB: Int
    public var pdfResolutionDownsampling: Bool
    public var videoRemoveAudio: Bool
    public var videoMaxResolutionEnabled: Bool
    public var videoMaxResolutionLines: Int
    /// When true, caps output frame rate via `videoMaxFPS` (only down-cap when source nominal FPS is higher).
    public var videoMaxFPSEnabled: Bool
    /// Target FPS when `videoMaxFPSEnabled`; must be one of ``VideoFPSCapPreset.allowedValues``.
    public var videoMaxFPS: Int
    /// Stored ``AudioConversionFormat`` raw (`aac_m4a`, `mp3`, …).
    public var audioFormatRaw: String
    /// Stored ``AudioConversionQualityTier`` raw (`smallest`, `balanced`, `archival`).
    public var audioQualityTierRaw: String
    public var pdfEnableOCR: Bool
    public var pdfOCRLanguages: [String]

    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        format: CompressionFormat,
        smartQuality: Bool,
        autoFormat: Bool,
        maxWidthEnabled: Bool,
        maxWidth: Int,
        maxFileSizeEnabled: Bool,
        maxFileSizeKB: Int,
        saveLocationRaw: String,
        filenameHandlingRaw: String,
        customSuffix: String,
        outputSubfolder: String = "",
        collisionNamingStyleRaw: String,
        collisionCustomPattern: String,
        stripMetadata: Bool,
        sanitizeFilenames: Bool,
        openFolderWhenDone: Bool,
        notifyWhenDone: Bool,
        watchFolderEnabled: Bool,
        watchFolderModeRaw: String,
        watchFolderPath: String,
        watchFolderBookmark: Data,
        presetCustomFolderPath: String,
        presetCustomFolderBookmark: Data,
        contentTypeHintRaw: String,
        chromaSubsamplingRaw: String = ChromaSubsampling.auto.rawValue,
        webpLossless: Bool = false,
        pngOutputModeRaw: String = PNGOutputMode.lossless.rawValue,
        presetMediaScopeRaw: String,
        pdfOutputModeRaw: String,
        pdfQualityRaw: String,
        videoQualityRaw: String,
        videoCodecFamilyRaw: String,
        pdfGrayscale: Bool,
        pdfAutoGrayscaleMonoScans: Bool,
        pdfPreserveExperimentalRaw: String,
        pdfMaxFileSizeEnabled: Bool,
        pdfMaxFileSizeKB: Int,
        pdfResolutionDownsampling: Bool,
        videoRemoveAudio: Bool,
        videoMaxResolutionEnabled: Bool,
        videoMaxResolutionLines: Int,
        videoMaxFPSEnabled: Bool,
        videoMaxFPS: Int,
        audioFormatRaw: String,
        audioQualityTierRaw: String,
        pdfEnableOCR: Bool,
        pdfOCRLanguages: [String],
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.format = format
        self.smartQuality = smartQuality
        self.autoFormat = autoFormat
        self.maxWidthEnabled = maxWidthEnabled
        self.maxWidth = maxWidth
        self.maxFileSizeEnabled = maxFileSizeEnabled
        self.maxFileSizeKB = maxFileSizeKB
        self.saveLocationRaw = saveLocationRaw
        self.filenameHandlingRaw = filenameHandlingRaw
        self.customSuffix = customSuffix
        self.outputSubfolder = outputSubfolder
        self.collisionNamingStyleRaw = collisionNamingStyleRaw
        self.collisionCustomPattern = collisionCustomPattern
        self.stripMetadata = stripMetadata
        self.sanitizeFilenames = sanitizeFilenames
        self.openFolderWhenDone = openFolderWhenDone
        self.notifyWhenDone = notifyWhenDone
        self.watchFolderEnabled = watchFolderEnabled
        self.watchFolderModeRaw = watchFolderModeRaw
        self.watchFolderPath = watchFolderPath
        self.watchFolderBookmark = watchFolderBookmark
        self.presetCustomFolderPath = presetCustomFolderPath
        self.presetCustomFolderBookmark = presetCustomFolderBookmark
        self.contentTypeHintRaw = contentTypeHintRaw
        self.chromaSubsamplingRaw = chromaSubsamplingRaw
        self.webpLossless = webpLossless
        self.pngOutputModeRaw = pngOutputModeRaw
        self.presetMediaScopeRaw = presetMediaScopeRaw
        self.pdfOutputModeRaw = pdfOutputModeRaw
        self.pdfQualityRaw = pdfQualityRaw
        self.videoQualityRaw = videoQualityRaw
        self.videoCodecFamilyRaw = videoCodecFamilyRaw
        self.pdfGrayscale = pdfGrayscale
        self.pdfAutoGrayscaleMonoScans = pdfAutoGrayscaleMonoScans
        self.pdfPreserveExperimentalRaw = pdfPreserveExperimentalRaw
        self.pdfMaxFileSizeEnabled = pdfMaxFileSizeEnabled
        self.pdfMaxFileSizeKB = pdfMaxFileSizeKB
        self.pdfResolutionDownsampling = pdfResolutionDownsampling
        self.videoRemoveAudio = videoRemoveAudio
        self.videoMaxResolutionEnabled = videoMaxResolutionEnabled
        self.videoMaxResolutionLines = videoMaxResolutionLines
        self.videoMaxFPSEnabled = videoMaxFPSEnabled
        self.videoMaxFPS = videoMaxFPS
        self.audioFormatRaw = audioFormatRaw
        self.audioQualityTierRaw = audioQualityTierRaw
        self.pdfEnableOCR = pdfEnableOCR
        self.pdfOCRLanguages = pdfOCRLanguages
        self.createdAt = createdAt
    }

    /// Deep copy for preset duplication: new identity and timestamp; all settings preserved.
    public init(duplicating source: CompressionPreset, name: String) {
        self.init(
            id: UUID(),
            name: name,
            format: source.format,
            smartQuality: source.smartQuality,
            autoFormat: source.autoFormat,
            maxWidthEnabled: source.maxWidthEnabled,
            maxWidth: source.maxWidth,
            maxFileSizeEnabled: source.maxFileSizeEnabled,
            maxFileSizeKB: source.maxFileSizeKB,
            saveLocationRaw: source.saveLocationRaw,
            filenameHandlingRaw: source.filenameHandlingRaw,
            customSuffix: source.customSuffix,
            outputSubfolder: source.outputSubfolder,
            collisionNamingStyleRaw: source.collisionNamingStyleRaw,
            collisionCustomPattern: source.collisionCustomPattern,
            stripMetadata: source.stripMetadata,
            sanitizeFilenames: source.sanitizeFilenames,
            openFolderWhenDone: source.openFolderWhenDone,
            notifyWhenDone: source.notifyWhenDone,
            watchFolderEnabled: source.watchFolderEnabled,
            watchFolderModeRaw: source.watchFolderModeRaw,
            watchFolderPath: source.watchFolderPath,
            watchFolderBookmark: source.watchFolderBookmark,
            presetCustomFolderPath: source.presetCustomFolderPath,
            presetCustomFolderBookmark: source.presetCustomFolderBookmark,
            contentTypeHintRaw: source.contentTypeHintRaw,
            chromaSubsamplingRaw: source.chromaSubsamplingRaw,
            webpLossless: source.webpLossless,
            pngOutputModeRaw: source.pngOutputModeRaw,
            presetMediaScopeRaw: source.presetMediaScopeRaw,
            pdfOutputModeRaw: source.pdfOutputModeRaw,
            pdfQualityRaw: source.pdfQualityRaw,
            videoQualityRaw: source.videoQualityRaw,
            videoCodecFamilyRaw: source.videoCodecFamilyRaw,
            pdfGrayscale: source.pdfGrayscale,
            pdfAutoGrayscaleMonoScans: source.pdfAutoGrayscaleMonoScans,
            pdfPreserveExperimentalRaw: source.pdfPreserveExperimentalRaw,
            pdfMaxFileSizeEnabled: source.pdfMaxFileSizeEnabled,
            pdfMaxFileSizeKB: source.pdfMaxFileSizeKB,
            pdfResolutionDownsampling: source.pdfResolutionDownsampling,
            videoRemoveAudio: source.videoRemoveAudio,
            videoMaxResolutionEnabled: source.videoMaxResolutionEnabled,
            videoMaxResolutionLines: source.videoMaxResolutionLines,
            videoMaxFPSEnabled: source.videoMaxFPSEnabled,
            videoMaxFPS: source.videoMaxFPS,
            audioFormatRaw: source.audioFormatRaw,
            audioQualityTierRaw: source.audioQualityTierRaw,
            pdfEnableOCR: source.pdfEnableOCR,
            pdfOCRLanguages: source.pdfOCRLanguages,
            createdAt: .now
        )
    }

    // Custom decoder so old presets (missing new fields) still load
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        format = try c.decode(CompressionFormat.self, forKey: .format)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        smartQuality = try c.decodeIfPresent(Bool.self, forKey: .smartQuality) ?? true
        autoFormat = try c.decodeIfPresent(Bool.self, forKey: .autoFormat) ?? false
        maxWidthEnabled = try c.decodeIfPresent(Bool.self, forKey: .maxWidthEnabled) ?? false
        maxWidth = try c.decodeIfPresent(Int.self, forKey: .maxWidth) ?? 1920
        maxFileSizeEnabled = try c.decodeIfPresent(Bool.self, forKey: .maxFileSizeEnabled) ?? false
        maxFileSizeKB = try c.decodeIfPresent(Int.self, forKey: .maxFileSizeKB) ?? 2048
        saveLocationRaw = try c.decodeIfPresent(String.self, forKey: .saveLocationRaw) ?? "sameFolder"
        filenameHandlingRaw = try c.decodeIfPresent(String.self, forKey: .filenameHandlingRaw) ?? "appendSuffix"
        customSuffix = try c.decodeIfPresent(String.self, forKey: .customSuffix) ?? "-dinky"
        outputSubfolder = try c.decodeIfPresent(String.self, forKey: .outputSubfolder) ?? ""
        collisionNamingStyleRaw = try c.decodeIfPresent(String.self, forKey: .collisionNamingStyleRaw)
            ?? CollisionNamingStyle.finderDuplicate.rawValue
        collisionCustomPattern = try c.decodeIfPresent(String.self, forKey: .collisionCustomPattern) ?? "_v{n}"
        stripMetadata = try c.decodeIfPresent(Bool.self, forKey: .stripMetadata) ?? false
        sanitizeFilenames = try c.decodeIfPresent(Bool.self, forKey: .sanitizeFilenames) ?? false
        openFolderWhenDone = try c.decodeIfPresent(Bool.self, forKey: .openFolderWhenDone) ?? false
        notifyWhenDone = try c.decodeIfPresent(Bool.self, forKey: .notifyWhenDone) ?? false
        watchFolderEnabled = try c.decodeIfPresent(Bool.self, forKey: .watchFolderEnabled) ?? false
        let rawMode = try c.decodeIfPresent(String.self, forKey: .watchFolderModeRaw) ?? "global"
        watchFolderModeRaw = (rawMode == "destination") ? "global" : rawMode
        watchFolderPath = try c.decodeIfPresent(String.self, forKey: .watchFolderPath) ?? ""
        watchFolderBookmark = try c.decodeIfPresent(Data.self, forKey: .watchFolderBookmark) ?? Data()
        presetCustomFolderPath = try c.decodeIfPresent(String.self, forKey: .presetCustomFolderPath) ?? ""
        presetCustomFolderBookmark = try c.decodeIfPresent(Data.self, forKey: .presetCustomFolderBookmark) ?? Data()
        contentTypeHintRaw = try c.decodeIfPresent(String.self, forKey: .contentTypeHintRaw) ?? "auto"
        chromaSubsamplingRaw = try c.decodeIfPresent(String.self, forKey: .chromaSubsamplingRaw)
            ?? ChromaSubsampling.auto.rawValue
        webpLossless = try c.decodeIfPresent(Bool.self, forKey: .webpLossless) ?? false
        pngOutputModeRaw = try c.decodeIfPresent(String.self, forKey: .pngOutputModeRaw)
            ?? PNGOutputMode.lossless.rawValue
        presetMediaScopeRaw = try c.decodeIfPresent(String.self, forKey: .presetMediaScopeRaw) ?? PresetMediaScope.all.rawValue
        pdfOutputModeRaw = try c.decodeIfPresent(String.self, forKey: .pdfOutputModeRaw) ?? "flattenPages"
        pdfQualityRaw = try c.decodeIfPresent(String.self, forKey: .pdfQualityRaw) ?? "medium"
        let storedVideoQuality = try c.decodeIfPresent(String.self, forKey: .videoQualityRaw) ?? "high"
        videoQualityRaw = Self.migratedVideoQualityRaw(storedVideoQuality)
        videoCodecFamilyRaw = try c.decodeIfPresent(String.self, forKey: .videoCodecFamilyRaw) ?? "h264"
        pdfGrayscale = try c.decodeIfPresent(Bool.self, forKey: .pdfGrayscale) ?? false
        pdfAutoGrayscaleMonoScans = try c.decodeIfPresent(Bool.self, forKey: .pdfAutoGrayscaleMonoScans) ?? true
        pdfPreserveExperimentalRaw = try c.decodeIfPresent(String.self, forKey: .pdfPreserveExperimentalRaw)
            ?? "none"
        pdfMaxFileSizeEnabled = try c.decodeIfPresent(Bool.self, forKey: .pdfMaxFileSizeEnabled) ?? false
        pdfMaxFileSizeKB = clampPDFMaxFileSizeKB(try c.decodeIfPresent(Int.self, forKey: .pdfMaxFileSizeKB) ?? 10240)
        pdfResolutionDownsampling = try c.decodeIfPresent(Bool.self, forKey: .pdfResolutionDownsampling) ?? false
        videoRemoveAudio = try c.decodeIfPresent(Bool.self, forKey: .videoRemoveAudio) ?? false
        videoMaxResolutionEnabled = try c.decodeIfPresent(Bool.self, forKey: .videoMaxResolutionEnabled) ?? false
        videoMaxResolutionLines = try c.decodeIfPresent(Int.self, forKey: .videoMaxResolutionLines) ?? 1080
        videoMaxFPSEnabled = try c.decodeIfPresent(Bool.self, forKey: .videoMaxFPSEnabled) ?? false
        videoMaxFPS = VideoFPSCapPreset.normalizeStored(
            try c.decodeIfPresent(Int.self, forKey: .videoMaxFPS) ?? VideoFPSCapPreset.defaultStoredFPS
        )
        audioFormatRaw = try c.decodeIfPresent(String.self, forKey: .audioFormatRaw)
            ?? AudioConversionFormat.aacM4A.rawValue
        audioQualityTierRaw = try c.decodeIfPresent(String.self, forKey: .audioQualityTierRaw)
            ?? AudioConversionQualityTier.balanced.rawValue
        pdfEnableOCR = try c.decodeIfPresent(Bool.self, forKey: .pdfEnableOCR) ?? true
        if let langs = try c.decodeIfPresent([String].self, forKey: .pdfOCRLanguages), !langs.isEmpty {
            pdfOCRLanguages = langs
        } else {
            pdfOCRLanguages = CompressionPreset.defaultPdfOCRLanguages
        }
    }

    private static func migratedVideoQualityRaw(_ stored: String) -> String {
        if stored == "high" || stored == "medium" { return stored }
        return "medium"
    }

    /// BCP-47 tags for Vision (e.g. `"en-US"`). Default Latin.
    public static let defaultPdfOCRLanguages: [String] = ["en-US"]

    public var includedMediaTypes: Set<MediaType> {
        PresetMediaScopeRawCodec.includedTypes(from: presetMediaScopeRaw)
    }

    public func applies(to media: MediaType) -> Bool {
        includedMediaTypes.contains(media)
    }
}
