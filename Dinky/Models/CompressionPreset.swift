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
    var watchFolderModeRaw: String   // "destination" | "unique"
    var watchFolderPath: String
    var watchFolderBookmark: Data
    // Custom output folder (per-preset, used when saveLocationRaw == "custom")
    var presetCustomFolderPath: String
    var presetCustomFolderBookmark: Data
    // Content type hint
    var contentTypeHintRaw: String

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
        self.watchFolderModeRaw = "destination"
        self.watchFolderPath = prefs.watchedFolderPath
        self.watchFolderBookmark = prefs.watchedFolderBookmark
        self.presetCustomFolderPath = ""
        self.presetCustomFolderBookmark = Data()
        self.contentTypeHintRaw = prefs.contentTypeHintRaw
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
        watchFolderModeRaw = try c.decodeIfPresent(String.self, forKey: .watchFolderModeRaw) ?? "destination"
        watchFolderPath = try c.decodeIfPresent(String.self, forKey: .watchFolderPath) ?? ""
        watchFolderBookmark = try c.decodeIfPresent(Data.self, forKey: .watchFolderBookmark) ?? Data()
        presetCustomFolderPath = try c.decodeIfPresent(String.self, forKey: .presetCustomFolderPath) ?? ""
        presetCustomFolderBookmark = try c.decodeIfPresent(Data.self, forKey: .presetCustomFolderBookmark) ?? Data()
        contentTypeHintRaw = try c.decodeIfPresent(String.self, forKey: .contentTypeHintRaw) ?? "auto"
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
        prefs.folderWatchEnabled = watchFolderEnabled
        if watchFolderModeRaw == "destination" {
            // Resolve destination folder for watch
            let destPath: String = {
                switch saveLocationRaw {
                case "downloads":
                    return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path ?? ""
                case "presetCustom":
                    return presetCustomFolderPath
                case "custom":
                    return prefs.customFolderDisplayPath
                default:
                    return ""  // "sameFolder" can't be pre-resolved
                }
            }()
            prefs.watchedFolderPath = destPath
            prefs.watchedFolderBookmark = Data()
        } else {
            prefs.watchedFolderPath = watchFolderPath
            prefs.watchedFolderBookmark = watchFolderBookmark
        }
        // "presetCustom" = preset has its own unique folder; override the global custom folder.
        // "custom" = use whatever is already set as the global custom folder — don't touch it.
        if saveLocationRaw == "presetCustom" {
            prefs.saveLocationRaw = "custom"
            prefs.customFolderBookmark = presetCustomFolderBookmark
            prefs.customFolderDisplayPath = presetCustomFolderPath
        }
        prefs.contentTypeHintRaw = contentTypeHintRaw
    }
}
