import DinkyCoreShared
import Foundation

extension CompressionPreset {
    init(name: String, from prefs: DinkyPreferences, format: CompressionFormat) {
        self.init(
            id: UUID(),
            name: name,
            format: format,
            smartQuality: true,
            autoFormat: prefs.autoFormat,
            maxWidthEnabled: prefs.maxWidthEnabled,
            maxWidth: prefs.maxWidth,
            maxFileSizeEnabled: prefs.maxFileSizeEnabled,
            maxFileSizeKB: prefs.maxFileSizeKB,
            saveLocationRaw: "sameFolder",
            filenameHandlingRaw: prefs.filenameHandlingRaw,
            customSuffix: prefs.customSuffix,
            collisionNamingStyleRaw: prefs.collisionNamingStyleRaw,
            collisionCustomPattern: prefs.collisionCustomPattern,
            stripMetadata: prefs.stripMetadata,
            sanitizeFilenames: prefs.sanitizeFilenames,
            openFolderWhenDone: prefs.openFolderWhenDone,
            notifyWhenDone: prefs.notifyWhenDone,
            watchFolderEnabled: prefs.folderWatchEnabled,
            watchFolderModeRaw: "global",
            watchFolderPath: prefs.watchedFolderPath,
            watchFolderBookmark: prefs.watchedFolderBookmark,
            presetCustomFolderPath: "",
            presetCustomFolderBookmark: Data(),
            contentTypeHintRaw: prefs.contentTypeHintRaw,
            chromaSubsamplingRaw: prefs.chromaSubsamplingRaw,
            webpLossless: prefs.webpLossless,
            pngOutputModeRaw: prefs.pngOutputModeRaw,
            presetMediaScopeRaw: PresetMediaScope.all.rawValue,
            pdfOutputModeRaw: prefs.pdfOutputModeRaw,
            pdfQualityRaw: prefs.pdfQualityRaw,
            videoQualityRaw: prefs.videoQualityRaw,
            videoCodecFamilyRaw: prefs.videoCodecFamilyRaw,
            pdfGrayscale: prefs.pdfGrayscale,
            pdfAutoGrayscaleMonoScans: prefs.pdfAutoGrayscaleMonoScans,
            pdfPreserveExperimentalRaw: prefs.pdfPreserveExperimentalRaw,
            pdfMaxFileSizeEnabled: prefs.pdfMaxFileSizeEnabled,
            pdfMaxFileSizeKB: clampPDFMaxFileSizeKB(prefs.pdfMaxFileSizeKB),
            pdfResolutionDownsampling: prefs.pdfResolutionDownsampling,
            videoRemoveAudio: prefs.videoRemoveAudio,
            videoMaxResolutionEnabled: prefs.videoMaxResolutionEnabled,
            videoMaxResolutionLines: prefs.videoMaxResolutionLines,
            videoMaxFPSEnabled: prefs.videoMaxFPSEnabled,
            videoMaxFPS: prefs.videoMaxFPS,
            audioFormatRaw: prefs.audioFormatRaw,
            audioQualityTierRaw: prefs.audioQualityTierRaw,
            pdfEnableOCR: prefs.pdfEnableOCR,
            pdfOCRLanguages: prefs.pdfOCRLanguages,
            createdAt: .now
        )
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
        prefs.collisionNamingStyleRaw = collisionNamingStyleRaw
        prefs.collisionCustomPattern = collisionCustomPattern
        prefs.stripMetadata = stripMetadata
        prefs.sanitizeFilenames = sanitizeFilenames
        prefs.openFolderWhenDone = openFolderWhenDone
        prefs.notifyWhenDone = notifyWhenDone
        if saveLocationRaw == "presetCustom" {
            prefs.saveLocationRaw = "custom"
            prefs.customFolderBookmark = presetCustomFolderBookmark
            prefs.customFolderDisplayPath = presetCustomFolderPath
        }
        prefs.contentTypeHintRaw = contentTypeHintRaw
        prefs.chromaSubsamplingRaw = chromaSubsamplingRaw
        prefs.webpLossless = webpLossless
        prefs.pngOutputModeRaw = pngOutputModeRaw
        prefs.pdfOutputModeRaw = pdfOutputModeRaw
        prefs.pdfQualityRaw = pdfQualityRaw
        prefs.videoQualityRaw = videoQualityRaw
        prefs.videoCodecFamilyRaw = videoCodecFamilyRaw
        prefs.pdfGrayscale = pdfGrayscale
        prefs.pdfAutoGrayscaleMonoScans = pdfAutoGrayscaleMonoScans
        prefs.pdfPreserveExperimentalRaw = pdfPreserveExperimentalRaw
        prefs.pdfMaxFileSizeEnabled = pdfMaxFileSizeEnabled
        prefs.pdfMaxFileSizeKB = pdfMaxFileSizeKB
        prefs.pdfResolutionDownsampling = pdfResolutionDownsampling
        prefs.videoRemoveAudio = videoRemoveAudio
        prefs.videoMaxResolutionEnabled = videoMaxResolutionEnabled
        prefs.videoMaxResolutionLines = videoMaxResolutionLines
        prefs.videoMaxFPSEnabled = videoMaxFPSEnabled
        prefs.videoMaxFPS = videoMaxFPS
        prefs.audioFormatRaw = audioFormatRaw
        prefs.audioQualityTierRaw = audioQualityTierRaw
        prefs.pdfEnableOCR = pdfEnableOCR
        prefs.pdfOCRLanguages = pdfOCRLanguages
    }

    /// Finder-style unique name among existing presets: `Name copy`, `Name copy 2`, …
    static func uniqueDuplicatePresetName(baseName: String, existingNames: Set<String>) -> String {
        let copyFrag = String(localized: " copy", comment: "Filename: first duplicate after base name, as in Finder “file copy”.")
        var n = 1
        while true {
            let candidate: String
            if n == 1 {
                candidate = baseName + copyFrag
            } else {
                candidate = baseName + copyFrag + " \(n)"
            }
            if !existingNames.contains(candidate) { return candidate }
            n += 1
        }
    }

    /// Short label for lists and sidebars: `All`, or comma-separated media names.
    var includedMediaTypesSummaryLabel: String {
        let inc = includedMediaTypes
        if inc == PresetMediaScopeRawCodec.allTypes {
            return PresetMediaScope.all.displayName
        }
        let order: [MediaType] = [.image, .video, .audio, .pdf]
        let names = order.filter { inc.contains($0) }.map(\.presetAppliesToSummaryWord)
        return names.joined(separator: String(localized: ", ", comment: "Separator between media types in preset subtitle."))
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

    func destinationDirectory(for source: URL, globalPrefs: DinkyPreferences, isFromURLDownload: Bool = false) -> URL {
        let base = baseDestinationDirectory(for: source, globalPrefs: globalPrefs, isFromURLDownload: isFromURLDownload)
        guard let subfolder = CompressionPreset.sanitizedOutputSubfolder(outputSubfolder) else { return base }
        return base.appendingPathComponent(subfolder, isDirectory: true)
    }

    private func baseDestinationDirectory(for source: URL, globalPrefs: DinkyPreferences, isFromURLDownload: Bool = false) -> URL {
        if isFromURLDownload, saveLocationRaw == "sameFolder" {
            return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                ?? source.deletingLastPathComponent()
        }
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

    func outputURL(for source: URL, format: CompressionFormat, globalPrefs: DinkyPreferences, isFromURLDownload: Bool = false) -> URL {
        let dir = destinationDirectory(for: source, globalPrefs: globalPrefs, isFromURLDownload: isFromURLDownload)
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

    func outputURL(for source: URL, mediaType: MediaType, globalPrefs: DinkyPreferences, isFromURLDownload: Bool = false) -> URL {
        switch mediaType {
        case .image:
            let dir = destinationDirectory(for: source, globalPrefs: globalPrefs, isFromURLDownload: isFromURLDownload)
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
            let dir = destinationDirectory(for: source, globalPrefs: globalPrefs, isFromURLDownload: isFromURLDownload)
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
            let dir = destinationDirectory(for: source, globalPrefs: globalPrefs, isFromURLDownload: isFromURLDownload)
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
        case .audio:
            let ext = AudioConversionFormat(rawValue: audioFormatRaw)?.fileExtension ?? "m4a"
            let dir = destinationDirectory(for: source, globalPrefs: globalPrefs, isFromURLDownload: isFromURLDownload)
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
            return dir.appendingPathComponent(out).appendingPathExtension(ext)
        }
    }
}
