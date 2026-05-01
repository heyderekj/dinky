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

// OriginalsAction and CollisionNamingStyle: see DinkyCoreImage (re-exported via DinkyCoreImageExports.swift).

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
        Self.migrateMoveOriginalsToOriginalsActionIfNeeded()
    }

    /// Migrates legacy `moveOriginalsToTrash` Bool to `originalsAction` once.
    private static func migrateMoveOriginalsToOriginalsActionIfNeeded() {
        let d = UserDefaults.standard
        let legacyKey = "moveOriginalsToTrash"
        guard d.object(forKey: legacyKey) != nil else { return }
        let wasTrash = d.bool(forKey: legacyKey)
        d.set(wasTrash ? OriginalsAction.trash.rawValue : OriginalsAction.keep.rawValue, forKey: "originalsAction")
        d.removeObject(forKey: legacyKey)
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
    @AppStorage("collisionNamingStyle") var collisionNamingStyleRaw: String = CollisionNamingStyle.finderDuplicate.rawValue
    var collisionNamingStyle: CollisionNamingStyle {
        get { CollisionNamingStyle(rawValue: collisionNamingStyleRaw) ?? .finderDuplicate }
        set { collisionNamingStyleRaw = newValue.rawValue }
    }
    /// Appended to the output basename when `collisionNamingStyle` is `.custom`.
    /// Include `{n}` for an incrementing number; without `{n}`, extra collisions get a space and trailing number (like Finder).
    @AppStorage("collisionCustomPattern") var collisionCustomPattern: String = "_v{n}"

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
    /// Finder **Get Info → Comments** (extended attributes), not embedded EXIF / PDF Info.
    @AppStorage("preserveFinderComments") var preserveFinderComments: Bool = false
    @AppStorage("preserveTimestamps")   var preserveTimestamps: Bool = true
    @AppStorage("originalsAction") private var originalsActionRaw: String = OriginalsAction.keep.rawValue
    var originalsAction: OriginalsAction {
        get { OriginalsAction(rawValue: originalsActionRaw) ?? .keep }
        set { originalsActionRaw = newValue.rawValue }
    }
    @AppStorage("originalsBackupFolderBookmark") var originalsBackupFolderBookmark: Data = Data()
    @AppStorage("originalsBackupFolderDisplayPath") var originalsBackupFolderDisplayPath: String = ""
    @AppStorage("minimumSavingsPercent") var minimumSavingsPercent: Int = 2
    @AppStorage("concurrentTasks")      var concurrentTasks: Int = 3

    /// Parallel compression cap — always one of `concurrentCompressionTiers` (legacy values snap).
    var concurrentCompressionLimit: Int { Self.normalizedConcurrentTasks(concurrentTasks) }

    /// When true, pending files are compressed largest-first so the batch tends to finish sooner (vs. smallest-first for quick early wins).
    @AppStorage("batchLargestFirst") var batchLargestFirst: Bool = false
    @AppStorage("playSoundEffects")     var playSoundEffects: Bool = true

    // MARK: Finish
    @AppStorage("openFolderWhenDone")   var openFolderWhenDone: Bool = true
    @AppStorage("showBatchSummaryDialog") var showBatchSummaryDialog: Bool = true
    @AppStorage("notifyWhenDone")       var notifyWhenDone: Bool = false
    @AppStorage("sanitizeFilenames")    var sanitizeFilenames: Bool = false
    @AppStorage("manualMode")           var manualMode: Bool = false
    /// When true (default), show the pre-compression confirmation for user-initiated adds. User can turn off in the sheet or Settings. Watch folder is unaffected.
    @AppStorage("confirmBeforeEveryCompression") var confirmBeforeEveryCompression: Bool = true
    /// Empties finished rows from the queue after a short delay when a batch completes.
    /// Failed/skipped rows are kept so the user can act on them.
    @AppStorage("autoClearWhenDone")    var autoClearWhenDone: Bool = false
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
    @AppStorage("pdfOutputMode")  var pdfOutputModeRaw: String = PDFOutputMode.flattenPages.rawValue
    var pdfOutputMode: PDFOutputMode {
        get { PDFOutputMode(rawValue: pdfOutputModeRaw) ?? .flattenPages }
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
    /// When Smart Quality is on, use grayscale flatten for PDFs that look like monochrome office scans (in addition to Grayscale PDFs).
    @AppStorage("pdfAutoGrayscaleMonoScans") var pdfAutoGrayscaleMonoScans: Bool = true
    /// Experimental qpdf options for preserve-text mode (see `PDFPreserveExperimentalMode`).
    @AppStorage("pdfPreserveExperimental") var pdfPreserveExperimentalRaw: String = PDFPreserveExperimentalMode.none.rawValue
    @AppStorage("pdfMaxFileSizeEnabled") var pdfMaxFileSizeEnabled: Bool = false
    @AppStorage("pdfMaxFileSizeKB") var pdfMaxFileSizeKB: Int = 10240  // 10 MB default
    var pdfMaxFileSizeMB: Double {
        get { Double(pdfMaxFileSizeKB) / 1024.0 }
        set { pdfMaxFileSizeKB = clampPDFMaxFileSizeKB(Int(newValue * 1024)) }
    }
    /// Preserve mode: rasterize image-heavy pages at 144 DPI while keeping text pages selectable.
    @AppStorage("pdfResolutionDownsampling") var pdfResolutionDownsampling: Bool = false
    /// Add Vision OCR text layer for documents that look like scans (before qpdf/flatten).
    @AppStorage("pdfEnableOCR") var pdfEnableOCR: Bool = true
    /// JSON array of BCP-47 language tags for Vision OCR.
    @AppStorage("pdfOCRLanguagesJSON") private var pdfOCRLanguagesJSON: String = "[\"en-US\"]"

    static let defaultPdfOCRLanguages: [String] = ["en-US"]

    var pdfOCRLanguages: [String] {
        get {
            guard let data = pdfOCRLanguagesJSON.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([String].self, from: data),
                  !decoded.isEmpty else { return Self.defaultPdfOCRLanguages }
            return decoded
        }
        set {
            let v = newValue.isEmpty ? Self.defaultPdfOCRLanguages : newValue
            if let data = try? JSONEncoder().encode(v), let s = String(data: data, encoding: .utf8) {
                pdfOCRLanguagesJSON = s
            }
        }
    }
    var pdfPreserveExperimental: PDFPreserveExperimentalMode {
        get { PDFPreserveExperimentalMode(rawValue: pdfPreserveExperimentalRaw) ?? .none }
        set { pdfPreserveExperimentalRaw = newValue.rawValue }
    }
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

    // MARK: Diagnostics
    /// Opt-in switch for receiving Apple's MetricKit crash diagnostics in-process.
    /// Off by default to keep Dinky's "no telemetry" promise — even when on, nothing
    /// leaves the Mac unless the user clicks Send in the post-crash sheet.
    @AppStorage("crashReportingEnabled") var crashReportingEnabled: Bool = false

    // MARK: Keyboard shortcuts (customizable menu commands)

    @AppStorage("shortcut.openFiles") private var shortcutOpenFilesData: Data = Data()
    @AppStorage("shortcut.pasteClipboard") private var shortcutPasteClipboardData: Data = Data()
    @AppStorage("shortcut.compressNow") private var shortcutCompressNowData: Data = Data()
    @AppStorage("shortcut.clearAll") private var shortcutClearAllData: Data = Data()
    @AppStorage("shortcut.deleteSelected") private var shortcutDeleteSelectedData: Data = Data()

    /// When on, `RegisterEventHotKey` mirrors “Clipboard Compress” so it works while another app is frontmost.
    @AppStorage("shortcut.pasteClipboardGlobal") var pasteClipboardGlobalEnabled: Bool = false

    func shortcut(for action: ShortcutAction) -> CustomShortcut {
        let data: Data
        switch action {
        case .openFiles: data = shortcutOpenFilesData
        case .pasteClipboard: data = shortcutPasteClipboardData
        case .compressNow: data = shortcutCompressNowData
        case .clearAll: data = shortcutClearAllData
        case .deleteSelected: data = shortcutDeleteSelectedData
        }
        if data.isEmpty { return action.defaultShortcut }
        return (try? JSONDecoder().decode(CustomShortcut.self, from: data)) ?? action.defaultShortcut
    }

    func setShortcut(_ shortcut: CustomShortcut, for action: ShortcutAction) {
        objectWillChange.send()
        let encoded = (try? JSONEncoder().encode(shortcut)) ?? Data()
        switch action {
        case .openFiles: shortcutOpenFilesData = encoded
        case .pasteClipboard: shortcutPasteClipboardData = encoded
        case .compressNow: shortcutCompressNowData = encoded
        case .clearAll: shortcutClearAllData = encoded
        case .deleteSelected: shortcutDeleteSelectedData = encoded
        }
        if action == .pasteClipboard {
            NotificationCenter.default.post(name: .dinkyGlobalPasteHotkeyChanged, object: nil)
        }
    }

    func resetShortcut(_ action: ShortcutAction) {
        objectWillChange.send()
        switch action {
        case .openFiles: shortcutOpenFilesData = Data()
        case .pasteClipboard: shortcutPasteClipboardData = Data()
        case .compressNow: shortcutCompressNowData = Data()
        case .clearAll: shortcutClearAllData = Data()
        case .deleteSelected: shortcutDeleteSelectedData = Data()
        }
        if action == .pasteClipboard {
            NotificationCenter.default.post(name: .dinkyGlobalPasteHotkeyChanged, object: nil)
        }
    }

    func resetAllShortcuts() {
        objectWillChange.send()
        shortcutOpenFilesData = Data()
        shortcutPasteClipboardData = Data()
        shortcutCompressNowData = Data()
        shortcutClearAllData = Data()
        shortcutDeleteSelectedData = Data()
        NotificationCenter.default.post(name: .dinkyGlobalPasteHotkeyChanged, object: nil)
    }

    func isDefaultShortcut(_ action: ShortcutAction) -> Bool {
        shortcut(for: action) == action.defaultShortcut
    }

    /// For `HelpWindow` to refresh when any stored shortcut changes.
    var shortcutHelpFingerprint: String {
        [
            shortcutOpenFilesData,
            shortcutPasteClipboardData,
            shortcutCompressNowData,
            shortcutClearAllData,
            shortcutDeleteSelectedData,
        ]
        .map { $0.base64EncodedString() }
        .joined(separator: "|")
    }

    // MARK: URL helpers

    /// When the user renames a security-scoped folder in Finder, the bookmark still resolves but stored path strings can lag. Refreshes paths and bookmark data (when stale). Safe to call often (e.g. app activation, folder watcher refresh).
    func reconcileFolderBookmarksIfNeeded() {
        if folderWatchEnabled, let r = Self.reanchorDirectory(bookmark: watchedFolderBookmark) {
            if r.path != watchedFolderPath { watchedFolderPath = r.path }
            if r.bookmark != watchedFolderBookmark { watchedFolderBookmark = r.bookmark }
        }
        if saveLocation == .custom, let r = Self.reanchorDirectory(bookmark: customFolderBookmark) {
            if r.path != customFolderDisplayPath { customFolderDisplayPath = r.path }
            if r.bookmark != customFolderBookmark { customFolderBookmark = r.bookmark }
        }
        if originalsAction == .backup, let r = Self.reanchorDirectory(bookmark: originalsBackupFolderBookmark) {
            if r.path != originalsBackupFolderDisplayPath { originalsBackupFolderDisplayPath = r.path }
            if r.bookmark != originalsBackupFolderBookmark { originalsBackupFolderBookmark = r.bookmark }
        }
        var presets = savedPresets
        var touched = false
        for i in presets.indices {
            if presets[i].watchFolderEnabled && presets[i].watchFolderModeRaw == "unique",
               let r = Self.reanchorDirectory(bookmark: presets[i].watchFolderBookmark) {
                if r.path != presets[i].watchFolderPath {
                    presets[i].watchFolderPath = r.path
                    touched = true
                }
                if r.bookmark != presets[i].watchFolderBookmark {
                    presets[i].watchFolderBookmark = r.bookmark
                    touched = true
                }
            }
            if presets[i].saveLocationRaw == "presetCustom",
               let r = Self.reanchorDirectory(bookmark: presets[i].presetCustomFolderBookmark) {
                if r.path != presets[i].presetCustomFolderPath {
                    presets[i].presetCustomFolderPath = r.path
                    touched = true
                }
                if r.bookmark != presets[i].presetCustomFolderBookmark {
                    presets[i].presetCustomFolderBookmark = r.bookmark
                    touched = true
                }
            }
        }
        if touched { savedPresets = presets }
    }

    private struct ReanchoredFolder {
        let path: String
        let bookmark: Data
    }

    /// Resolved, existing directory path and bookmark data (refreshed when the system marks the bookmark stale).
    private static func reanchorDirectory(bookmark: Data) -> ReanchoredFolder? {
        guard !bookmark.isEmpty else { return nil }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return nil }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return nil }
        let std = (url.path as NSString).standardizingPath
        let bm = (stale ? (try? url.bookmarkData(options: .withSecurityScope)) : nil) ?? bookmark
        return ReanchoredFolder(path: std, bookmark: bm)
    }

    func resolvedCustomFolder() -> URL? {
        guard !customFolderBookmark.isEmpty else { return nil }
        var stale = false
        return try? URL(resolvingBookmarkData: customFolderBookmark,
                        options: .withSecurityScope, relativeTo: nil,
                        bookmarkDataIsStale: &stale)
    }

    /// Default backup folder when the user hasn't picked one: `~/Pictures/Dinky Originals`.
    func defaultOriginalsBackupFolderURL() -> URL {
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures", isDirectory: true)
        return pictures.appendingPathComponent("Dinky Originals", isDirectory: true)
    }

    /// Resolved bookmark for originals backup, or the default folder URL.
    func originalsBackupDestinationURL() -> URL {
        if !originalsBackupFolderBookmark.isEmpty {
            var stale = false
            if let u = try? URL(resolvingBookmarkData: originalsBackupFolderBookmark,
                                 options: .withSecurityScope, relativeTo: nil,
                                 bookmarkDataIsStale: &stale) {
                return u
            }
        }
        return defaultOriginalsBackupFolderURL()
    }

    /// Where compressed output should land. When `isFromURLDownload` is true and `sameFolder` is selected,
    /// `sameFolder` is meaningless (source is in temp) — fall back to Downloads.
    func destinationDirectory(for source: URL, isFromURLDownload: Bool = false) -> URL {
        if isFromURLDownload, saveLocation == .sameFolder {
            return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                ?? source.deletingLastPathComponent()
        }
        switch saveLocation {
        case .sameFolder: return source.deletingLastPathComponent()
        case .downloads:  return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                               ?? source.deletingLastPathComponent()
        case .custom:     return resolvedCustomFolder() ?? source.deletingLastPathComponent()
        }
    }

    func outputURL(for source: URL, format: CompressionFormat, isFromURLDownload: Bool = false) -> URL {
        let dir  = destinationDirectory(for: source, isFromURLDownload: isFromURLDownload)
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

    func outputURL(for source: URL, mediaType: MediaType, isFromURLDownload: Bool = false) -> URL {
        switch mediaType {
        case .image:
            // Shouldn't be called for image — use outputURL(for:format:) instead.
            // Fallback: keep original extension.
            let dir  = destinationDirectory(for: source, isFromURLDownload: isFromURLDownload)
            let stem = source.deletingPathExtension().lastPathComponent
            var out: String
            switch filenameHandling {
            case .appendSuffix:  out = stem + "-dinky"
            case .replaceOrigin: out = stem
            case .customSuffix:  out = stem + (customSuffix.isEmpty ? "-dinky" : customSuffix)
            }
            return dir.appendingPathComponent(out).appendingPathExtension(source.pathExtension.lowercased())
        case .pdf:
            let dir  = destinationDirectory(for: source, isFromURLDownload: isFromURLDownload)
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
            let dir  = destinationDirectory(for: source, isFromURLDownload: isFromURLDownload)
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
        goals: CompressionGoals,
        parallelCompressionLimit: Int
    ) {
        let d = UserDefaults.standard
        let strip = d.object(forKey: "stripMetadata") as? Bool ?? false
        let smart = d.object(forKey: "smartQuality") as? Bool ?? true
        let hint = d.string(forKey: "contentTypeHint") ?? "auto"
        let maxWOn = d.object(forKey: "maxWidthEnabled") as? Bool ?? false
        let maxW = maxWOn ? (d.object(forKey: "maxWidth") as? Int ?? 1920) : nil
        let maxFSOn = d.object(forKey: "maxFileSizeEnabled") as? Bool ?? false
        let maxFS = maxFSOn ? (d.object(forKey: "maxFileSizeKB") as? Int ?? 2048) : nil
        let concurrentRaw = d.object(forKey: "concurrentTasks") as? Int ?? 3
        let parallelLimit = normalizedConcurrentTasks(concurrentRaw)
        return (strip, smart, hint, CompressionGoals(maxWidth: maxW, maxFileSizeKB: maxFS), parallelLimit)
    }

    /// PDF compression defaults for Shortcuts — same keys as `@AppStorage` on this type.
    static func pdfCompressionSettingsForIntent() -> (
        outputMode: PDFOutputMode,
        quality: PDFQuality,
        grayscale: Bool,
        stripMetadata: Bool,
        preserveExperimental: PDFPreserveExperimentalMode,
        smartQuality: Bool,
        pdfAutoGrayscaleMonoScans: Bool,
        pdfEnableOCR: Bool,
        pdfOCRLanguages: [String]
    ) {
        let d = UserDefaults.standard
        let modeRaw = d.string(forKey: "pdfOutputMode") ?? PDFOutputMode.flattenPages.rawValue
        let mode = PDFOutputMode(rawValue: modeRaw) ?? .flattenPages
        let qRaw = d.string(forKey: "pdfQuality") ?? PDFQuality.medium.rawValue
        let quality = PDFQuality(rawValue: qRaw) ?? .medium
        let grayscale = d.object(forKey: "pdfGrayscale") as? Bool ?? false
        let strip = d.object(forKey: "stripMetadata") as? Bool ?? false
        let expRaw = d.string(forKey: "pdfPreserveExperimental") ?? PDFPreserveExperimentalMode.none.rawValue
        let experimental = PDFPreserveExperimentalMode(rawValue: expRaw) ?? .none
        let smart = d.object(forKey: "smartQuality") as? Bool ?? true
        let autoMono = d.object(forKey: "pdfAutoGrayscaleMonoScans") as? Bool ?? true
        let ocrOn = d.object(forKey: "pdfEnableOCR") as? Bool ?? true
        let json = d.string(forKey: "pdfOCRLanguagesJSON") ?? "[\"en-US\"]"
        let langs: [String] = {
            guard let data = json.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([String].self, from: data),
                  !decoded.isEmpty else { return defaultPdfOCRLanguages }
            return decoded
        }()
        return (mode, quality, grayscale, strip, experimental, smart, autoMono, ocrOn, langs)
    }

    /// Video compression defaults for Shortcuts — same keys as `@AppStorage` on this type.
    static func videoCompressionSettingsForIntent() -> (
        quality: VideoQuality,
        codec: VideoCodecFamily,
        removeAudio: Bool,
        maxResolutionLines: Int?
    ) {
        let d = UserDefaults.standard
        let vqRaw = d.string(forKey: "videoQuality") ?? VideoQuality.high.rawValue
        let quality = VideoQuality.resolve(vqRaw)
        let codecRaw = d.string(forKey: "videoCodecFamily") ?? VideoCodecFamily.h264.rawValue
        let codec = VideoCodecFamily(rawValue: codecRaw) ?? .h264
        let removeAudio = d.object(forKey: "videoRemoveAudio") as? Bool ?? false
        let maxOn = d.object(forKey: "videoMaxResolutionEnabled") as? Bool ?? false
        let lines = d.object(forKey: "videoMaxResolutionLines") as? Int ?? 1080
        let maxRes: Int? = maxOn ? lines : nil
        return (quality, codec, removeAudio, maxRes)
    }

    // MARK: - Compression confirmation summary (shared with sidebar output hints)

    /// One line: where outputs are saved (matches sidebar “Where files go”).
    func outputDestinationSummaryLine() -> String {
        switch saveLocation {
        case .sameFolder:
            return String(localized: "Saves next to originals", comment: "Output summary: save location.")
        case .downloads:
            return String(localized: "Saves to Downloads", comment: "Output summary: save location.")
        case .custom:
            return customFolderDisplayPath.isEmpty
                ? String(localized: "Custom folder (not set in Settings)", comment: "Output summary: custom folder unset.")
                : URL(fileURLWithPath: customFolderDisplayPath).lastPathComponent
        }
    }

    /// One line: filename handling (matches sidebar).
    func outputFilenameSummaryLine() -> String {
        switch filenameHandling {
        case .appendSuffix:
            return String(localized: "Adds “-dinky” before the extension", comment: "Output summary: filename handling.")
        case .replaceOrigin:
            return String(localized: "Replaces the original", comment: "Output summary: filename handling.")
        case .customSuffix:
            return String.localizedStringWithFormat(
                String(localized: "Custom suffix: %@", comment: "Output summary; argument is suffix string."),
                customSuffix
            )
        }
    }

    func originalsAfterSuccessSummaryLine() -> String {
        switch originalsAction {
        case .keep:
            return String(localized: "After success: originals stay where they are", comment: "Compression confirm: originals policy.")
        case .trash:
            return String(localized: "After success: originals move to Trash", comment: "Compression confirm: originals policy.")
        case .backup:
            return String(localized: "After success: originals move to your Backup folder", comment: "Compression confirm: originals policy.")
        }
    }

    /// Still-image policy for the confirmation sheet (convert-first).
    func imageCompressionPolicySummaryLine(selectedFormat: CompressionFormat) -> String {
        if autoFormat {
            return String(localized: "Images: converts to AVIF for photos and WebP for most other images (Auto)", comment: "Compression confirm: image formats.")
        }
        return String.localizedStringWithFormat(
            String(localized: "Images: converts to %@", comment: "Compression confirm: fixed image format; argument is format name."),
            selectedFormat.displayName
        )
    }

    /// PDF + video one-liner (legacy; prefer ``videoCompressionPolicySummaryRows()`` / ``pdfCompressionPolicySummaryRows()``).
    func pdfAndVideoCompressionSummaryLine() -> String {
        let v = videoCompressionPolicySummaryRows().joined(separator: " ")
        let p = pdfCompressionPolicySummaryRows().joined(separator: " ")
        if v.isEmpty, p.isEmpty {
            return String(localized: "PDFs and videos: use your current Settings and sidebar options (Smart Quality may adjust tiers).", comment: "Compression confirm: PDF/video.")
        }
        return [v, p].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Short lines for the pre-compression sheet when the queue includes videos (container is always `.mp4`).
    func videoCompressionPolicySummaryRows() -> [String] {
        let codec = videoCodecFamily
        var rows: [String] = [
            String.localizedStringWithFormat(
                String(localized: "Videos: %@ → .mp4", comment: "Compression confirm: video codec and container."),
                codec.chipLabel
            ),
        ]
        if smartQuality {
            rows.append(
                String(localized: "Videos: Smart Quality picks Balanced or High per clip (HDR uses HEVC when needed).", comment: "Compression confirm: video smart quality.")
            )
        } else {
            rows.append(
                String.localizedStringWithFormat(
                    String(localized: "Videos: fixed encoder strength — %@", comment: "Compression confirm: video manual quality; argument is tier name."),
                    videoQuality.displayName
                )
            )
        }
        if videoMaxResolutionEnabled {
            rows.append(
                String.localizedStringWithFormat(
                    String(localized: "Videos: max height %lldp", comment: "Compression confirm: video resolution cap."),
                    Int64(videoMaxResolutionLines)
                )
            )
        }
        if videoRemoveAudio {
            rows.append(String(localized: "Videos: audio stripped from output", comment: "Compression confirm: video strip audio."))
        }
        return rows
    }

    /// Short lines for the pre-compression sheet when the queue includes PDFs.
    func pdfCompressionPolicySummaryRows() -> [String] {
        switch pdfOutputMode {
        case .preserveStructure:
            var rows: [String] = [
                String(localized: "PDFs: preserve text and links when smaller (qpdf + PDFKit)", comment: "Compression confirm: PDF preserve mode."),
            ]
            if pdfEnableOCR {
                rows.append(String(localized: "PDFs: search scanned pages (OCR) when needed", comment: "Compression confirm: PDF OCR."))
            }
            return rows
        case .flattenPages:
            var rows: [String] = []
            if smartQuality {
                rows.append(
                    String.localizedStringWithFormat(
                        String(localized: "PDFs: flatten with Smart Quality (manual fallback: %@)", comment: "Compression confirm: PDF flatten + smart; argument is PDF tier."),
                        pdfQuality.displayName
                    )
                )
            } else {
                rows.append(
                    String.localizedStringWithFormat(
                        String(localized: "PDFs: flatten pages (%@ JPEG)", comment: "Compression confirm: PDF flatten tier; argument is tier name."),
                        pdfQuality.displayName
                    )
                )
            }
            if pdfGrayscale {
                rows.append(String(localized: "PDFs: grayscale for flatten when appropriate", comment: "Compression confirm: PDF grayscale."))
            }
            if pdfMaxFileSizeEnabled {
                rows.append(
                    String.localizedStringWithFormat(
                        String(localized: "PDFs: step down tiers to try to stay under %.1f MB", comment: "Compression confirm: PDF max size cap."),
                        pdfMaxFileSizeMB
                    )
                )
            }
            return rows
        }
    }

    /// When the queue is links only (types unknown until download).
    func remoteLinksCompressionPolicySummaryLine() -> String {
        String(localized: "Links: output follows your Settings for each file after download.", comment: "Compression confirm: remote-only queue.")
    }

    /// Per-row subtitle for a queued video (matches global prefs).
    func videoPendingRowSubtitleLine() -> String {
        let codec = videoCodecFamily
        let head = String.localizedStringWithFormat(
            String(localized: "Video → %@ · .mp4", comment: "Compression confirm: video row; codec."),
            codec.chipLabel
        )
        if smartQuality {
            return head + " · " + String(localized: "Smart", comment: "Compression confirm: smart quality short label.")
        }
        return head + " · " + videoQuality.displayName
    }

    /// Per-row subtitle for a queued PDF (matches global prefs).
    func pdfPendingRowSubtitleLine() -> String {
        switch pdfOutputMode {
        case .preserveStructure:
            return String(localized: "PDF → Preserve text", comment: "Compression confirm: PDF row preserve.")
        case .flattenPages:
            return String.localizedStringWithFormat(
                String(localized: "PDF → Flatten (%@)", comment: "Compression confirm: PDF row flatten; argument is tier."),
                pdfQuality.displayName
            )
        }
    }

    /// Manual mode hint when enabled.
    func manualModeQueueSummaryLine() -> String? {
        guard manualMode else { return nil }
        return String(localized: "Manual mode: new files stay queued until you choose Compress Now", comment: "Compression confirm: manual mode.")
    }

    /// Bullets for the pre-compression sheet (order matters). Kept for compatibility; the sheet uses typed rows instead.
    func compressionConfirmationBulletLines(selectedFormat: CompressionFormat) -> [String] {
        var lines: [String] = [
            outputDestinationSummaryLine(),
            outputFilenameSummaryLine(),
            originalsAfterSuccessSummaryLine(),
            imageCompressionPolicySummaryLine(selectedFormat: selectedFormat),
            pdfAndVideoCompressionSummaryLine(),
        ]
        if let m = manualModeQueueSummaryLine() {
            lines.append(m)
        }
        return lines
    }
}
