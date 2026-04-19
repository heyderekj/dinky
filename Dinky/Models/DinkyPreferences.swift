import Foundation
import SwiftUI

enum SaveLocation: String, CaseIterable, Identifiable {
    case sameFolder = "sameFolder"
    case downloads  = "downloads"
    case custom     = "custom"
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .sameFolder: return "Same folder as original"
        case .downloads:  return "Downloads folder"
        case .custom:     return "Custom folder…"
        }
    }
}

enum FilenameHandling: String, CaseIterable, Identifiable {
    case appendSuffix  = "appendSuffix"
    case replaceOrigin = "replaceOrigin"
    case customSuffix  = "customSuffix"
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .appendSuffix:  return "Append suffix (default: -dinky)"
        case .replaceOrigin: return "Replace original"
        case .customSuffix:  return "Custom suffix"
        }
    }
}

final class DinkyPreferences: ObservableObject {

    /// Stored `concurrentTasks` values allowed in Settings (legacy ints snap to these).
    static let concurrentCompressionTiers: [Int] = [1, 3, 8]

    /// Maps any stored value to the nearest tier (1, 3, or 8).
    static func normalizedConcurrentTasks(_ raw: Int) -> Int {
        switch raw {
        case ...0: return 3
        case 1: return 1
        case 2...4: return 3
        default: return 8
        }
    }

    init() {
        Self.migrateConcurrentTasksToTiersIfNeeded()
    }

    private static func migrateConcurrentTasksToTiersIfNeeded() {
        let key = "concurrentTasks"
        let d = UserDefaults.standard
        guard d.object(forKey: key) != nil else { return }
        let raw = d.integer(forKey: key)
        let snapped = normalizedConcurrentTasks(raw)
        if snapped != raw { d.set(snapped, forKey: key) }
    }

    // MARK: Output
    @AppStorage("saveLocation")         var saveLocationRaw: String = SaveLocation.sameFolder.rawValue
    var saveLocation: SaveLocation {
        get { SaveLocation(rawValue: saveLocationRaw) ?? .sameFolder }
        set { saveLocationRaw = newValue.rawValue }
    }
    @AppStorage("customFolderBookmark")    var customFolderBookmark: Data = Data()
    @AppStorage("customFolderDisplayPath") var customFolderDisplayPath: String = ""
    @AppStorage("filenameHandling")     var filenameHandlingRaw: String = FilenameHandling.appendSuffix.rawValue
    var filenameHandling: FilenameHandling {
        get { FilenameHandling(rawValue: filenameHandlingRaw) ?? .appendSuffix }
        set { filenameHandlingRaw = newValue.rawValue }
    }
    @AppStorage("customSuffix")         var customSuffix: String = "-dinky"

    // MARK: Format
    @AppStorage("defaultFormat")        var defaultFormatRaw: String = CompressionFormat.webp.rawValue
    var defaultFormat: CompressionFormat {
        get { CompressionFormat(rawValue: defaultFormatRaw) ?? .webp }
        set { defaultFormatRaw = newValue.rawValue }
    }

    // MARK: Goals
    @AppStorage("maxWidthEnabled")      var maxWidthEnabled: Bool = false
    @AppStorage("maxWidth")             var maxWidth: Int = 1920
    @AppStorage("maxFileSizeEnabled")   var maxFileSizeEnabled: Bool = false
    @AppStorage("maxFileSizeKB")        var maxFileSizeKB: Int = 2048   // 2 MB default

    var maxFileSizeMB: Double {
        get { Double(maxFileSizeKB) / 1024.0 }
        set { maxFileSizeKB = max(1, Int(newValue * 1024)) }
    }

    // MARK: Compression behavior
    @AppStorage("stripMetadata")        var stripMetadata: Bool = false
    @AppStorage("preserveTimestamps")   var preserveTimestamps: Bool = true
    @AppStorage("moveOriginalsToTrash") var moveOriginalsToTrash: Bool = false
    @AppStorage("minimumSavingsPercent") var minimumSavingsPercent: Int = 2
    @AppStorage("concurrentTasks")      var concurrentTasks: Int = 3

    /// Parallel compression cap — always one of `concurrentCompressionTiers` (legacy values snap).
    var concurrentCompressionLimit: Int { Self.normalizedConcurrentTasks(concurrentTasks) }
    @AppStorage("playSoundEffects")     var playSoundEffects: Bool = true

    // MARK: Finish
    @AppStorage("openFolderWhenDone")   var openFolderWhenDone: Bool = false
    @AppStorage("notifyWhenDone")       var notifyWhenDone: Bool = false
    @AppStorage("sanitizeFilenames")    var sanitizeFilenames: Bool = false
    @AppStorage("manualMode")           var manualMode: Bool = false
    @AppStorage("reduceMotion")         var reduceMotion: Bool = false
    @AppStorage("folderWatchEnabled")   var folderWatchEnabled: Bool = false
    @AppStorage("watchedFolderPath")    var watchedFolderPath: String = ""
    @AppStorage("watchedFolderBookmark") var watchedFolderBookmark: Data = Data()

    // MARK: Smart quality
    @AppStorage("smartQuality")         var smartQuality: Bool = true
    @AppStorage("autoFormat")           var autoFormat: Bool = true
    @AppStorage("contentTypeHint")      var contentTypeHintRaw: String = "auto"

    // MARK: Sidebar visibility
    @AppStorage("sidebar.showImages") var showImagesSection: Bool = true
    @AppStorage("sidebar.showPDFs")   var showPDFsSection:   Bool = true
    @AppStorage("sidebar.showVideos") var showVideosSection:  Bool = true

    /// Simplified in-window sidebar (default): quick choices, output summary, and Settings shortcuts.
    @AppStorage("sidebar.simpleMode") var sidebarSimpleMode: Bool = true

    /// When enabling simple sidebar, scoped sections are turned off; when disabling it, all sections turn back on.
    func applySidebarSimpleMode(_ simple: Bool) {
        sidebarSimpleMode = simple
        if simple {
            showImagesSection = false
            showVideosSection = false
            showPDFsSection = false
        } else {
            showImagesSection = true
            showVideosSection = true
            showPDFsSection = true
        }
    }

    /// Migrates older preferences where simple mode was on but section toggles were still true.
    func reconcileSidebarSectionsForSimpleModeIfNeeded() {
        guard sidebarSimpleMode else { return }
        if showImagesSection || showVideosSection || showPDFsSection {
            showImagesSection = false
            showVideosSection = false
            showPDFsSection = false
        }
    }

    /// Turning off Images, Videos, and PDFs in the full sidebar enables simple mode (same as choosing it explicitly).
    func adoptSimpleSidebarWhenAllSectionsHidden() {
        guard !showImagesSection, !showVideosSection, !showPDFsSection else { return }
        applySidebarSimpleMode(true)
    }

    enum SidebarScopedSection {
        case images, videos, pdfs
    }

    /// Updates Images / Videos / PDFs visibility. Turning any section **on** while simple sidebar is active leaves simple mode off and only changes that toggle (others unchanged).
    func setScopedSidebarSection(_ section: SidebarScopedSection, isOn: Bool) {
        if isOn && sidebarSimpleMode {
            sidebarSimpleMode = false
        }
        switch section {
        case .images: showImagesSection = isOn
        case .videos: showVideosSection = isOn
        case .pdfs: showPDFsSection = isOn
        }
        adoptSimpleSidebarWhenAllSectionsHidden()
    }

    // MARK: PDF / Video quality + options
    @AppStorage("pdfOutputMode")  var pdfOutputModeRaw: String = PDFOutputMode.preserveStructure.rawValue
    var pdfOutputMode: PDFOutputMode {
        get { PDFOutputMode(rawValue: pdfOutputModeRaw) ?? .preserveStructure }
        set { pdfOutputModeRaw = newValue.rawValue }
    }
    @AppStorage("pdfQuality")     var pdfQualityRaw: String  = PDFQuality.medium.rawValue
    var pdfQuality: PDFQuality {
        get { PDFQuality(rawValue: pdfQualityRaw) ?? .medium }
        set { pdfQualityRaw = newValue.rawValue }
    }
    /// Manual fallback when Smart Quality is off, also used as the Smart Quality fallback if analysis fails.
    /// `.low` was removed because its artifacts didn't fit a quality-first compressor — `VideoQuality.resolve`
    /// migrates any persisted `"low"` to `.medium`.
    @AppStorage("videoQuality")    var videoQualityRaw: String = VideoQuality.high.rawValue
    var videoQuality: VideoQuality {
        get { VideoQuality.resolve(videoQualityRaw) }
        set { videoQualityRaw = newValue.rawValue }
    }
    @AppStorage("videoCodecFamily") var videoCodecFamilyRaw: String = VideoCodecFamily.h264.rawValue
    var videoCodecFamily: VideoCodecFamily {
        get { VideoCodecFamily(rawValue: videoCodecFamilyRaw) ?? .h264 }
        set { videoCodecFamilyRaw = newValue.rawValue }
    }
    @AppStorage("pdfGrayscale")    var pdfGrayscale:    Bool = false
    @AppStorage("videoRemoveAudio") var videoRemoveAudio: Bool = false

    /// Optional video downscale (mirrors images' Max width). Off → keeps source resolution.
    @AppStorage("videoMaxResolutionEnabled") var videoMaxResolutionEnabled: Bool = false
    /// Output height in pixels (matches one of the available `AVAssetExportPreset…` heights: 480 / 720 / 1080 / 2160).
    @AppStorage("videoMaxResolutionLines")   var videoMaxResolutionLines: Int = 1080

    // MARK: Lifetime stats
    @AppStorage("lifetimeSavedBytesRaw") var lifetimeSavedBytesRaw: Double = 0
    var lifetimeSavedBytes: Int64 {
        get { Int64(lifetimeSavedBytesRaw) }
        set { lifetimeSavedBytesRaw = Double(newValue) }
    }

    // MARK: Presets
    @AppStorage("activePresetID") var activePresetID: String = ""
    @AppStorage("savedPresetsData") var savedPresetsData: Data = Data()

    private var cachedSavedPresets: [CompressionPreset]?
    var savedPresets: [CompressionPreset] {
        get {
            if let cachedSavedPresets { return cachedSavedPresets }
            let v = (try? JSONDecoder().decode([CompressionPreset].self, from: savedPresetsData)) ?? []
            cachedSavedPresets = v
            return v
        }
        set {
            cachedSavedPresets = newValue
            savedPresetsData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    // MARK: Session history
    @AppStorage("sessionHistoryData") var sessionHistoryData: Data = Data()

    private var cachedSessionHistory: [SessionRecord]?
    var sessionHistory: [SessionRecord] {
        get {
            if let cachedSessionHistory { return cachedSessionHistory }
            let v = (try? JSONDecoder().decode([SessionRecord].self, from: sessionHistoryData)) ?? []
            cachedSessionHistory = v
            return v
        }
        set {
            cachedSessionHistory = newValue
            sessionHistoryData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    // MARK: Updates
    @AppStorage("lastUpdateCheck")         var lastUpdateCheck: Double = 0
    @AppStorage("dismissedUpdateVersion")  var dismissedUpdateVersion: String = ""

    // MARK: URL helpers

    func resolvedCustomFolder() -> URL? {
        guard !customFolderBookmark.isEmpty else { return nil }
        var stale = false
        return try? URL(resolvingBookmarkData: customFolderBookmark,
                        options: .withSecurityScope, relativeTo: nil,
                        bookmarkDataIsStale: &stale)
    }

    func destinationDirectory(for source: URL) -> URL {
        switch saveLocation {
        case .sameFolder: return source.deletingLastPathComponent()
        case .downloads:  return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                               ?? source.deletingLastPathComponent()
        case .custom:     return resolvedCustomFolder() ?? source.deletingLastPathComponent()
        }
    }

    func outputURL(for source: URL, format: CompressionFormat) -> URL {
        let dir  = destinationDirectory(for: source)
        let stem = source.deletingPathExtension().lastPathComponent
        var out: String
        switch filenameHandling {
        case .appendSuffix:  out = stem + "-dinky"
        case .replaceOrigin: out = stem
        case .customSuffix:  out = stem + (customSuffix.isEmpty ? "-dinky" : customSuffix)
        }
        if sanitizeFilenames {
            out = out.lowercased().replacingOccurrences(of: " ", with: "-")
            if out.count > 75 { out = String(out.prefix(75)) }
        }
        return dir.appendingPathComponent(out).appendingPathExtension(format.outputExtension)
    }

    func outputURL(for source: URL, mediaType: MediaType) -> URL {
        switch mediaType {
        case .image:
            // Shouldn't be called for image — use outputURL(for:format:) instead.
            // Fallback: keep original extension.
            let dir  = destinationDirectory(for: source)
            let stem = source.deletingPathExtension().lastPathComponent
            var out: String
            switch filenameHandling {
            case .appendSuffix:  out = stem + "-dinky"
            case .replaceOrigin: out = stem
            case .customSuffix:  out = stem + (customSuffix.isEmpty ? "-dinky" : customSuffix)
            }
            return dir.appendingPathComponent(out).appendingPathExtension(source.pathExtension.lowercased())
        case .pdf:
            let dir  = destinationDirectory(for: source)
            let stem = source.deletingPathExtension().lastPathComponent
            var out: String
            switch filenameHandling {
            case .appendSuffix:  out = stem + "-dinky"
            case .replaceOrigin: out = stem
            case .customSuffix:  out = stem + (customSuffix.isEmpty ? "-dinky" : customSuffix)
            }
            if sanitizeFilenames {
                out = out.lowercased().replacingOccurrences(of: " ", with: "-")
                if out.count > 75 { out = String(out.prefix(75)) }
            }
            return dir.appendingPathComponent(out).appendingPathExtension("pdf")
        case .video:
            // Always output as .mp4 (H.264 or H.265 per video codec preference)
            let dir  = destinationDirectory(for: source)
            let stem = source.deletingPathExtension().lastPathComponent
            var out: String
            switch filenameHandling {
            case .appendSuffix:  out = stem + "-dinky"
            case .replaceOrigin: out = stem
            case .customSuffix:  out = stem + (customSuffix.isEmpty ? "-dinky" : customSuffix)
            }
            if sanitizeFilenames {
                out = out.lowercased().replacingOccurrences(of: " ", with: "-")
                if out.count > 75 { out = String(out.prefix(75)) }
            }
            return dir.appendingPathComponent(out).appendingPathExtension("mp4")
        }
    }

    // MARK: - App Intents / Shortcuts

    /// Reads the same `UserDefaults` keys as `@AppStorage` so Shortcuts match in-app compression defaults.
    static func compressionSettingsForIntent() -> (
        stripMetadata: Bool,
        smartQuality: Bool,
        contentTypeHint: String,
        goals: CompressionGoals
    ) {
        let d = UserDefaults.standard
        let strip = d.object(forKey: "stripMetadata") as? Bool ?? false
        let smart = d.object(forKey: "smartQuality") as? Bool ?? true
        let hint = d.string(forKey: "contentTypeHint") ?? "auto"
        let maxWOn = d.object(forKey: "maxWidthEnabled") as? Bool ?? false
        let maxW = maxWOn ? (d.object(forKey: "maxWidth") as? Int ?? 1920) : nil
        let maxFSOn = d.object(forKey: "maxFileSizeEnabled") as? Bool ?? false
        let maxFS = maxFSOn ? (d.object(forKey: "maxFileSizeKB") as? Int ?? 2048) : nil
        return (strip, smart, hint, CompressionGoals(maxWidth: maxW, maxFileSizeKB: maxFS))
    }
}
