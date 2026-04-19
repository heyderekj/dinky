import Foundation

struct CompressionPreset: Codable, Identifiable {
    let id: UUID
    var name: String
    // Format
    var format: CompressionFormat
    var smartQuality: Bool
    var autoFormat: Bool
    // Limits
    var maxWidthEnabled: Bool
    var maxWidth: Int
    var maxFileSizeEnabled: Bool
    var maxFileSizeKB: Int
    // Output
    var saveLocationRaw: String
    var filenameHandlingRaw: String
    var customSuffix: String
    // Advanced
    var stripMetadata: Bool
    var sanitizeFilenames: Bool
    var openFolderWhenDone: Bool
    // Notifications
    var notifyWhenDone: Bool
    // Watch folder (per-preset)
    var watchFolderEnabled: Bool
    var watchFolderModeRaw: String   // "global" | "unique"
    var watchFolderPath: String
    var watchFolderBookmark: Data
    // Custom output folder (per-preset, used when saveLocationRaw == "custom")
    var presetCustomFolderPath: String
    var presetCustomFolderBookmark: Data
    // Content type hint
    var contentTypeHintRaw: String
    /// Which media types this preset targets (`all` | `image` | `pdf` | `video`).
    var presetMediaScopeRaw: String
    // PDF / Video (same keys as DinkyPreferences)
    var pdfOutputModeRaw: String
    var pdfQualityRaw: String
    var videoQualityRaw: String
    var videoCodecFamilyRaw: String
    var pdfGrayscale: Bool
    var videoRemoveAudio: Bool
    /// Mirrors images' Max width: opt-in cap on output video height.
    var videoMaxResolutionEnabled: Bool
    var videoMaxResolutionLines: Int

    let createdAt: Date

    init(name: String, from prefs: DinkyPreferences, format: CompressionFormat) {
        self.id = UUID()
        self.name = name
        self.format = format
        self.smartQuality = true
        self.autoFormat = prefs.autoFormat
        self.maxWidthEnabled = prefs.maxWidthEnabled
        self.maxWidth = prefs.maxWidth
        self.maxFileSizeEnabled = prefs.maxFileSizeEnabled
        self.maxFileSizeKB = prefs.maxFileSizeKB
        self.saveLocationRaw = "sameFolder"
        self.filenameHandlingRaw = prefs.filenameHandlingRaw
        self.customSuffix = prefs.customSuffix
        self.stripMetadata = prefs.stripMetadata
        self.sanitizeFilenames = prefs.sanitizeFilenames
        self.openFolderWhenDone = prefs.openFolderWhenDone
        self.notifyWhenDone = prefs.notifyWhenDone
        self.watchFolderEnabled = prefs.folderWatchEnabled
        self.watchFolderModeRaw = "global"
        self.watchFolderPath = prefs.watchedFolderPath
        self.watchFolderBookmark = prefs.watchedFolderBookmark
        self.presetCustomFolderPath = ""
        self.presetCustomFolderBookmark = Data()
        self.contentTypeHintRaw = prefs.contentTypeHintRaw
        self.presetMediaScopeRaw = PresetMediaScope.all.rawValue
        self.pdfOutputModeRaw = prefs.pdfOutputModeRaw
        self.pdfQualityRaw = prefs.pdfQualityRaw
        self.videoQualityRaw = prefs.videoQualityRaw
        self.videoCodecFamilyRaw = prefs.videoCodecFamilyRaw
        self.pdfGrayscale = prefs.pdfGrayscale
        self.videoRemoveAudio = prefs.videoRemoveAudio
        self.videoMaxResolutionEnabled = prefs.videoMaxResolutionEnabled
        self.videoMaxResolutionLines = prefs.videoMaxResolutionLines
        self.createdAt = .now
    }

    // Custom decoder so old presets (missing new fields) still load
    init(from decoder: Decoder) throws {
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
        presetMediaScopeRaw = try c.decodeIfPresent(String.self, forKey: .presetMediaScopeRaw) ?? PresetMediaScope.all.rawValue
        pdfOutputModeRaw = try c.decodeIfPresent(String.self, forKey: .pdfOutputModeRaw) ?? PDFOutputMode.preserveStructure.rawValue
        pdfQualityRaw = try c.decodeIfPresent(String.self, forKey: .pdfQualityRaw) ?? PDFQuality.medium.rawValue
        let storedVideoQuality = try c.decodeIfPresent(String.self, forKey: .videoQualityRaw) ?? VideoQuality.high.rawValue
        // Migrates a persisted `"low"` (removed tier) to the closest remaining tier (`.medium`).
        videoQualityRaw = VideoQuality.resolve(storedVideoQuality).rawValue
        videoCodecFamilyRaw = try c.decodeIfPresent(String.self, forKey: .videoCodecFamilyRaw) ?? VideoCodecFamily.h264.rawValue
        pdfGrayscale = try c.decodeIfPresent(Bool.self, forKey: .pdfGrayscale) ?? false
        videoRemoveAudio = try c.decodeIfPresent(Bool.self, forKey: .videoRemoveAudio) ?? false
        videoMaxResolutionEnabled = try c.decodeIfPresent(Bool.self, forKey: .videoMaxResolutionEnabled) ?? false
        videoMaxResolutionLines = try c.decodeIfPresent(Int.self, forKey: .videoMaxResolutionLines) ?? 1080
    }

    func apply(to prefs: DinkyPreferences, selectedFormat: inout CompressionFormat) {
        selectedFormat = format
        prefs.smartQuality = smartQuality
        prefs.autoFormat = autoFormat
        prefs.maxWidthEnabled = maxWidthEnabled
        prefs.maxWidth = maxWidth
        prefs.maxFileSizeEnabled = maxFileSizeEnabled
        prefs.maxFileSizeKB = maxFileSizeKB
        prefs.saveLocationRaw = saveLocationRaw
        prefs.filenameHandlingRaw = filenameHandlingRaw
        prefs.customSuffix = customSuffix
        prefs.stripMetadata = stripMetadata
        prefs.sanitizeFilenames = sanitizeFilenames
        prefs.openFolderWhenDone = openFolderWhenDone
        prefs.notifyWhenDone = notifyWhenDone
        // Folder watch is managed separately (global path + optional per-preset unique paths).
        // "presetCustom" = preset has its own unique folder; override the global custom folder.
        // "custom" = use whatever is already set as the global custom folder — don't touch it.
        if saveLocationRaw == "presetCustom" {
            prefs.saveLocationRaw = "custom"
            prefs.customFolderBookmark = presetCustomFolderBookmark
            prefs.customFolderDisplayPath = presetCustomFolderPath
        }
        prefs.contentTypeHintRaw = contentTypeHintRaw
        prefs.pdfOutputModeRaw = pdfOutputModeRaw
        prefs.pdfQualityRaw = pdfQualityRaw
        prefs.videoQualityRaw = videoQualityRaw
        prefs.videoCodecFamilyRaw = videoCodecFamilyRaw
        prefs.pdfGrayscale = pdfGrayscale
        prefs.videoRemoveAudio = videoRemoveAudio
        prefs.videoMaxResolutionEnabled = videoMaxResolutionEnabled
        prefs.videoMaxResolutionLines = videoMaxResolutionLines
    }
}

// MARK: - Output paths (same rules as `DinkyPreferences`, with per-preset destination)

extension CompressionPreset {

    /// Whether this preset should run for the given file type (watch routing, etc.).
    func applies(to media: MediaType) -> Bool {
        guard let scope = PresetMediaScope(rawValue: presetMediaScopeRaw) else { return true }
        switch scope {
        case .all: return true
        case .image: return media == .image
        case .pdf: return media == .pdf
        case .video: return media == .video
        }
    }

    func resolvedPresetCustomFolder() -> URL? {
        guard !presetCustomFolderBookmark.isEmpty else { return nil }
        var stale = false
        return try? URL(
            resolvingBookmarkData: presetCustomFolderBookmark,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
    }

    func destinationDirectory(for source: URL, globalPrefs: DinkyPreferences) -> URL {
        switch saveLocationRaw {
        case "sameFolder":
            return source.deletingLastPathComponent()
        case "downloads":
            return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                ?? source.deletingLastPathComponent()
        case "custom":
            return globalPrefs.resolvedCustomFolder() ?? source.deletingLastPathComponent()
        case "presetCustom":
            return resolvedPresetCustomFolder() ?? source.deletingLastPathComponent()
        default:
            return source.deletingLastPathComponent()
        }
    }

    private var filenameHandling: FilenameHandling {
        FilenameHandling(rawValue: filenameHandlingRaw) ?? .appendSuffix
    }

    func outputURL(for source: URL, format: CompressionFormat, globalPrefs: DinkyPreferences) -> URL {
        let dir = destinationDirectory(for: source, globalPrefs: globalPrefs)
        let stem = source.deletingPathExtension().lastPathComponent
        var out: String
        switch filenameHandling {
        case .appendSuffix: out = stem + "-dinky"
        case .replaceOrigin: out = stem
        case .customSuffix: out = stem + (customSuffix.isEmpty ? "-dinky" : customSuffix)
        }
        if sanitizeFilenames {
            out = out.lowercased().replacingOccurrences(of: " ", with: "-")
            if out.count > 75 { out = String(out.prefix(75)) }
        }
        return dir.appendingPathComponent(out).appendingPathExtension(format.outputExtension)
    }

    func outputURL(for source: URL, mediaType: MediaType, globalPrefs: DinkyPreferences) -> URL {
        switch mediaType {
        case .image:
            let dir = destinationDirectory(for: source, globalPrefs: globalPrefs)
            let stem = source.deletingPathExtension().lastPathComponent
            var out: String
            switch filenameHandling {
            case .appendSuffix: out = stem + "-dinky"
            case .replaceOrigin: out = stem
            case .customSuffix: out = stem + (customSuffix.isEmpty ? "-dinky" : customSuffix)
            }
            if sanitizeFilenames {
                out = out.lowercased().replacingOccurrences(of: " ", with: "-")
                if out.count > 75 { out = String(out.prefix(75)) }
            }
            return dir.appendingPathComponent(out).appendingPathExtension(source.pathExtension.lowercased())
        case .pdf:
            let dir = destinationDirectory(for: source, globalPrefs: globalPrefs)
            let stem = source.deletingPathExtension().lastPathComponent
            var out: String
            switch filenameHandling {
            case .appendSuffix: out = stem + "-dinky"
            case .replaceOrigin: out = stem
            case .customSuffix: out = stem + (customSuffix.isEmpty ? "-dinky" : customSuffix)
            }
            if sanitizeFilenames {
                out = out.lowercased().replacingOccurrences(of: " ", with: "-")
                if out.count > 75 { out = String(out.prefix(75)) }
            }
            return dir.appendingPathComponent(out).appendingPathExtension("pdf")
        case .video:
            let dir = destinationDirectory(for: source, globalPrefs: globalPrefs)
            let stem = source.deletingPathExtension().lastPathComponent
            var out: String
            switch filenameHandling {
            case .appendSuffix: out = stem + "-dinky"
            case .replaceOrigin: out = stem
            case .customSuffix: out = stem + (customSuffix.isEmpty ? "-dinky" : customSuffix)
            }
            if sanitizeFilenames {
                out = out.lowercased().replacingOccurrences(of: " ", with: "-")
                if out.count > 75 { out = String(out.prefix(75)) }
            }
            return dir.appendingPathComponent(out).appendingPathExtension("mp4")
        }
    }
}
