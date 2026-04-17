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
    @AppStorage("concurrentTasks")      var concurrentTasks: Int = max(1, min(8, ProcessInfo.processInfo.activeProcessorCount))
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

    // MARK: Lifetime stats
    @AppStorage("lifetimeSavedBytesRaw") var lifetimeSavedBytesRaw: Double = 0
    var lifetimeSavedBytes: Int64 {
        get { Int64(lifetimeSavedBytesRaw) }
        set { lifetimeSavedBytesRaw = Double(newValue) }
    }

    // MARK: Presets
    @AppStorage("activePresetID") var activePresetID: String = ""
    @AppStorage("savedPresetsData") var savedPresetsData: Data = Data()
    var savedPresets: [CompressionPreset] {
        get { (try? JSONDecoder().decode([CompressionPreset].self, from: savedPresetsData)) ?? [] }
        set { savedPresetsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    // MARK: Session history
    @AppStorage("sessionHistoryData") var sessionHistoryData: Data = Data()
    var sessionHistory: [SessionRecord] {
        get { (try? JSONDecoder().decode([SessionRecord].self, from: sessionHistoryData)) ?? [] }
        set { sessionHistoryData = (try? JSONEncoder().encode(newValue)) ?? Data() }
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
}
