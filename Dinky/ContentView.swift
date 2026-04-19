import SwiftUI
import UniformTypeIdentifiers
import UserNotifications
import Darwin
import AppKit
import PDFKit

enum PasteClipboardResult {
    case added
    case emptyClipboard
    case duplicateInQueue
}

// MARK: - AsyncSemaphore

private actor AsyncSemaphore {
    private var count: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []
    init(limit: Int) { count = limit }
    func wait() async {
        if count > 0 { count -= 1; return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func signal() {
        if waiters.isEmpty { count += 1 } else { waiters.removeFirst().resume() }
    }
}

@MainActor
final class ContentViewModel: ObservableObject {
    @Published var items: [ImageItem] = []
    @Published var isProcessing = false
    @Published var phase: DropZonePhase = .idle
    private var compressionStartTime: Date = .now

    /// Limits parallel `URLDownloader` work when many links are dropped at once.
    private static let remoteDownloadSemaphore = AsyncSemaphore(limit: 4)

    var selectedFormat: CompressionFormat
    var prefs: DinkyPreferences

    init(prefs: DinkyPreferences) {
        self.prefs = prefs
        self.selectedFormat = prefs.defaultFormat
    }

    /// Hardware video encoders are limited; parallel `AVAssetExportSession`s usually hurt throughput.
    static var concurrentVideoExportLimit: Int {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        guard size > 1 else { return 1 }
        var buf = [CChar](repeating: 0, count: size)
        let err = sysctlbyname("machdep.cpu.brand_string", &buf, &size, nil, 0)
        guard err == 0 else { return 1 }
        let brand = String(cString: buf)
        if brand.contains("Pro") || brand.contains("Max") || brand.contains("Ultra") {
            return 2
        }
        return 1
    }

    var isEmpty: Bool { items.isEmpty }

    var presentMediaTypes: Set<MediaType> {
        Set(items.map { $0.mediaType })
    }

    func addAndCompress(_ urls: [URL], force: Bool = false, presetID: UUID? = nil) {
        var seen = Set(items.map(\.sourceURL.path))
        let newURLs = urls.filter { url in
            let p = url.path
            guard !seen.contains(p) else { return false }
            seen.insert(p)
            return true
        }
        guard !newURLs.isEmpty else { return }
        let new = newURLs.map { CompressionItem(sourceURL: $0, presetID: presetID) }
        if force { new.forEach { $0.forceCompress = true } }
        items.append(contentsOf: new)
        // Smallest files first — quick wins land early, the big ones stack
        // up at the bottom. This is also the order they'll be processed in.
        items.sort { $0.originalSize < $1.originalSize }
        if !prefs.manualMode { compress() }
    }

    func compressItems(_ targets: [CompressionItem], format: CompressionFormat) {
        for item in targets {
            item.formatOverride = format
        }
        compress()
    }

    func recompress(_ item: CompressionItem, as format: CompressionFormat) {
        item.formatOverride = format
        item.forceCompress = true
        item.status = .pending
        compress()
    }

    func effectivePDFOutputMode(for item: CompressionItem) -> PDFOutputMode {
        let p = item.presetID.flatMap { id in prefs.savedPresets.first(where: { $0.id == id }) }
        return p.map { PDFOutputMode(rawValue: $0.pdfOutputModeRaw) ?? .preserveStructure } ?? prefs.pdfOutputMode
    }

    func queuePDFCompressAtQuality(_ targets: [CompressionItem], quality: PDFQuality) {
        for item in targets where item.mediaType == .pdf && effectivePDFOutputMode(for: item) == .flattenPages {
            item.pdfQualityOverride = quality
        }
        compress()
    }

    func recompressPDF(_ item: CompressionItem, quality: PDFQuality) {
        item.pdfQualityOverride = quality
        item.forceCompress = true
        item.status = .pending
        compress()
    }

    func queueVideoCompress(_ targets: [CompressionItem], quality: VideoQuality, codec: VideoCodecFamily) {
        for item in targets where item.mediaType == .video {
            item.videoRecompressOverride = (quality, codec)
        }
        compress()
    }

    func recompressVideo(_ item: CompressionItem, quality: VideoQuality, codec: VideoCodecFamily) {
        item.videoRecompressOverride = (quality, codec)
        item.forceCompress = true
        item.status = .pending
        compress()
    }

    func forceCompress(_ item: CompressionItem) {
        item.forceCompress = true
        item.status = .pending
        compress()
    }

    func clear() {
        cleanupPasteTemps(for: items)
        items = []
        phase = .idle
    }

    func remove(_ item: CompressionItem) {
        item.downloadTask?.cancel()
        item.downloadTask = nil
        cleanupPasteTemps(for: [item])
        items.removeAll { $0.id == item.id }
        if items.isEmpty { phase = .idle }
    }

    func pasteClipboard() -> PasteClipboardResult {
        guard let imp = ClipboardImporter.importFromClipboard() else { return .emptyClipboard }
        switch imp {
        case .localFile(let url):
            if items.contains(where: { $0.sourceURL.path == url.path }) { return .duplicateInQueue }
            addAndCompress([url])
            return .added
        case .remoteURL(let url):
            if items.contains(where: { $0.pendingRemoteURL == url }) { return .duplicateInQueue }
            queueRemoteDownload(urls: [url], force: false)
            return .added
        }
    }

    /// Download remote `http(s)` media URLs (max 4 concurrent), then queue for compression.
    func queueRemoteDownload(urls: [URL], force: Bool) {
        for url in urls {
            let placeholder = FileManager.default.temporaryDirectory
                .appendingPathComponent("dinky_dl_placeholder_\(UUID().uuidString)")
            let item = CompressionItem(sourceURL: placeholder, presetID: nil, mediaType: .image)
            item.pendingRemoteURL = url
            item.isURLDownloadSource = true
            item.status = .downloading(progress: 0, bytesReceived: 0, totalBytes: nil, displayHost: url.host ?? "…")
            if force { item.forceCompress = true }
            items.append(item)

            let host = url.host ?? "…"
            item.downloadTask = Task { [weak self] in
                guard let self else { return }
                await Self.remoteDownloadSemaphore.wait()
                do {
                    let local = try await URLDownloader.download(url) { progress, total in
                        Task { @MainActor in
                            guard let it = self.items.first(where: { $0.id == item.id }) else { return }
                            let received: Int64
                            if let t = total, t > 0 {
                                received = Int64((Double(t) * progress).rounded(.down))
                            } else {
                                received = 0
                            }
                            it.status = .downloading(
                                progress: progress,
                                bytesReceived: received,
                                totalBytes: total,
                                displayHost: host
                            )
                        }
                    }
                    await MainActor.run {
                        guard let idx = self.items.firstIndex(where: { $0.id == item.id }) else { return }
                        let row = self.items[idx]
                        row.sourceURL = local
                        row.mediaType = MediaTypeDetector.detect(local) ?? .image
                        if row.mediaType == .pdf {
                            row.pageCount = PDFDocument(url: local)?.pageCount
                        }
                        row.pendingRemoteURL = nil
                        row.downloadTask = nil
                        row.status = .pending
                        if !self.prefs.manualMode { self.compress() }
                    }
                } catch is CancellationError {
                    await MainActor.run { self.remove(item) }
                } catch {
                    await MainActor.run {
                        guard let idx = self.items.firstIndex(where: { $0.id == item.id }) else { return }
                        self.items[idx].status = .failed(Self.userFacingDownloadFailure(error))
                        self.items[idx].downloadTask = nil
                    }
                }
                await Self.remoteDownloadSemaphore.signal()
            }
        }
        // Re-sort by placeholder size (0) — keep order
    }

    private static func userFacingDownloadFailure(_ error: Error) -> Error {
        if let le = error as? LocalizedError, let d = le.errorDescription, !d.isEmpty {
            return NSError(domain: "Dinky", code: 0, userInfo: [NSLocalizedDescriptionKey: d])
        }
        return error
    }

    /// Removes selected items except those currently compressing (matches row context menu rules).
    func removeSelection(with ids: Set<UUID>) {
        let toRemove = items.filter { item in
            guard ids.contains(item.id) else { return false }
            if case .processing = item.status { return false }
            return true
        }
        for item in toRemove { remove(item) }
    }

    private func cleanupPasteTemps(for targets: [CompressionItem]) {
        let tmp = FileManager.default.temporaryDirectory.path
        for item in targets {
            if item.sourceURL.path.hasPrefix(tmp) {
                try? FileManager.default.removeItem(at: item.sourceURL)
            }
        }
    }

    // MARK: - Compress

    func compress() {
        guard !isProcessing else { return }
        let pending = items.filter { if case .pending = $0.status { return true }; return false }
        // Nothing to do — don't flicker the drop zone into a `.done` "All done!"
        // screen when the user fires Compress Now with an empty queue.
        guard !pending.isEmpty else { return }
        isProcessing = true
        phase = .processing
        compressionStartTime = .now

        let batchPreset = batchSharedPreset(from: pending)

        Task {
            await withTaskGroup(of: Void.self) { group in
                let mediaSem = AsyncSemaphore(limit: prefs.concurrentCompressionLimit)
                let videoSem = AsyncSemaphore(limit: Self.concurrentVideoExportLimit)
                for item in pending {
                    let mediaType = item.mediaType
                    switch mediaType {
                    case .video:
                        await videoSem.wait()
                    case .image, .pdf:
                        await mediaSem.wait()
                    }
                    group.addTask { [weak self] in
                        defer {
                            switch mediaType {
                            case .video:
                                Task { await videoSem.signal() }
                            case .image, .pdf:
                                Task { await mediaSem.signal() }
                            }
                        }
                        await self?.compressItem(item)
                    }
                }
            }
            await MainActor.run {
                self.isProcessing = false
                // If the queue was emptied mid-run (Clear All, autoClear race, etc.),
                // don't strand the empty drop zone in `.done` — fall back to idle.
                self.phase = self.items.isEmpty ? .idle : .done
                let batchSaved = self.items.reduce(Int64(0)) { $0 + $1.savedBytes }
                self.prefs.lifetimeSavedBytes += batchSaved

                let doneCount = self.items.filter { if case .done = $0.status { return true }; return false }.count
                if doneCount > 0 {
                    let formats = Array(Set(self.items.compactMap { item -> String? in
                        guard case .done = item.status else { return nil }
                        switch item.mediaType {
                        case .image: return (item.formatOverride ?? self.selectedFormat).displayName
                        case .pdf:   return "PDF"
                        case .video: return "Video"
                        }
                    })).sorted()
                    let record = SessionRecord(id: UUID(), timestamp: .now,
                                              fileCount: doneCount,
                                              totalBytesSaved: batchSaved,
                                              formats: formats)
                    var history = self.prefs.sessionHistory
                    history.insert(record, at: 0)
                    self.prefs.sessionHistory = Array(history.prefix(50))
                }

                if self.prefs.playSoundEffects { self.playCompletionSound(savedBytes: batchSaved) }

                let elapsed = Date.now.timeIntervalSince(self.compressionStartTime)
                let doneItems = self.items.compactMap { item -> URL? in
                    if case .done(let url, _, _) = item.status { return url } else { return nil }
                }

                let openFolder = batchPreset?.openFolderWhenDone ?? self.prefs.openFolderWhenDone
                if openFolder, let first = doneItems.first {
                    NSWorkspace.shared.open(first.deletingLastPathComponent())
                }

                let notify = batchPreset?.notifyWhenDone ?? self.prefs.notifyWhenDone
                if notify {
                    self.sendNotification(count: doneItems.count, seconds: elapsed)
                }

                if self.prefs.autoClearWhenDone, doneItems.isEmpty == false {
                    self.scheduleAutoClearAfterBatch()
                }
            }
        }
    }

    /// Removes successfully-finished rows after a short delay so the user has a moment to glance at the results.
    /// Failed/skipped/downloading rows are intentionally kept so they remain actionable.
    private func scheduleAutoClearAfterBatch() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let self else { return }
            // A new batch may have started in the meantime; bail rather than yanking rows mid-process.
            guard !self.isProcessing else { return }
            let toRemove = self.items.filter {
                if case .done = $0.status { return true }
                return false
            }
            guard toRemove.isEmpty == false else { return }
            for item in toRemove { self.remove(item) }
            if self.items.isEmpty { self.phase = .idle }
        }
    }

    /// When every pending item shares the same `presetID`, use that preset for batch-level options (notifications / open folder).
    private func batchSharedPreset(from items: [CompressionItem]) -> CompressionPreset? {
        guard let firstId = items.first?.presetID else { return nil }
        guard items.allSatisfy({ $0.presetID == firstId }) else { return nil }
        return prefs.savedPresets.first(where: { $0.id == firstId })
    }

    private func activePreset(for item: CompressionItem) -> CompressionPreset? {
        item.presetID.flatMap { id in prefs.savedPresets.first(where: { $0.id == id }) }
    }

    private func compressionGoals(for item: CompressionItem) -> CompressionGoals {
        if let p = activePreset(for: item) {
            return CompressionGoals(
                maxWidth: p.maxWidthEnabled ? p.maxWidth : nil,
                maxFileSizeKB: p.maxFileSizeEnabled ? p.maxFileSizeKB : nil
            )
        }
        return CompressionGoals(
            maxWidth: prefs.maxWidthEnabled ? prefs.maxWidth : nil,
            maxFileSizeKB: prefs.maxFileSizeEnabled ? prefs.maxFileSizeKB : nil
        )
    }

    private func compressItem(_ item: CompressionItem) async {
        let goals = compressionGoals(for: item)
        switch item.mediaType {
        case .image:
            await compressImageItem(item, goals: goals)
        case .pdf:
            await compressPDFItem(item)
        case .video:
            await compressVideoItem(item)
        }
    }

    private func compressImageItem(_ item: CompressionItem, goals: CompressionGoals) async {
        let wasForced = await MainActor.run { () -> Bool in
            let f = item.forceCompress
            item.forceCompress = false
            return f
        }
        let preset = activePreset(for: item)
        let autoFmt = preset?.autoFormat ?? prefs.autoFormat
        let smartQ = preset?.smartQuality ?? prefs.smartQuality
        let hint = preset?.contentTypeHintRaw ?? prefs.contentTypeHintRaw
        let strip = preset?.stripMetadata ?? prefs.stripMetadata

        var format = item.formatOverride ?? preset?.format ?? selectedFormat
        var preclassifiedForSmartQ: ContentType? = nil
        if autoFmt, item.formatOverride == nil {
            let ct = ContentClassifier.classify(item.sourceURL)
            await MainActor.run { item.detectedContentType = ct }
            format = ct == .photo ? .avif : .webp
            if smartQ { preclassifiedForSmartQ = ct }
        }

        if format == .png && item.sourceURL.pathExtension.lowercased() != "png" {
            await MainActor.run { item.status = .failed(PNGInputError()) }
            return
        }

        await MainActor.run { item.status = .processing }
        let urlDL = item.isURLDownloadSource
        let outputURL: URL = {
            if let pr = preset { return pr.outputURL(for: item.sourceURL, format: format, globalPrefs: prefs, isFromURLDownload: urlDL) }
            return prefs.outputURL(for: item.sourceURL, format: format, isFromURLDownload: urlDL)
        }()
        let replaceOrigin = (preset.map { FilenameHandling(rawValue: $0.filenameHandlingRaw) } ?? prefs.filenameHandling) == .replaceOrigin
        let backupURL = prefs.originalsAction == .backup ? prefs.originalsBackupDestinationURL() : nil
        do {
            let result = try await CompressionService.shared.compress(
                source: item.sourceURL,
                format: format,
                goals: goals,
                stripMetadata: strip,
                outputURL: outputURL,
                originalsAction: prefs.originalsAction,
                backupFolderURL: backupURL,
                isURLDownloadSource: urlDL,
                smartQuality: smartQ,
                contentTypeHint: hint,
                preclassifiedContent: preclassifiedForSmartQ
            )
            let savings = result.originalSize > 0
                ? Double(result.originalSize - result.outputSize) / Double(result.originalSize) : 0
            await MainActor.run {
                item.detectedContentType = result.detectedContentType
                if result.outputSize >= result.originalSize {
                    item.status = .zeroGain(attemptedSize: result.outputSize)
                    try? FileManager.default.removeItem(at: result.outputURL)
                } else if self.prefs.minimumSavingsPercent > 0 && savings < Double(self.prefs.minimumSavingsPercent) / 100.0 && !wasForced {
                    item.status = .skipped(savedPercent: savings * 100, threshold: self.prefs.minimumSavingsPercent)
                    try? FileManager.default.removeItem(at: result.outputURL)
                } else {
                    item.status = .done(outputURL: result.outputURL,
                                        originalSize: result.originalSize,
                                        outputSize: result.outputSize)
                    if self.prefs.preserveTimestamps {
                        self.copyTimestamp(from: item.sourceURL, to: result.outputURL)
                    }
                    if replaceOrigin {
                        if urlDL {
                            try? FileManager.default.removeItem(at: item.sourceURL)
                        } else {
                            try? OriginalsHandler.disposeForReplace(
                                originalAt: item.sourceURL,
                                action: self.prefs.originalsAction,
                                backupFolder: self.prefs.originalsAction == .backup ? self.prefs.originalsBackupDestinationURL() : nil
                            )
                        }
                    }
                }
            }
        } catch {
            await MainActor.run { item.status = .failed(error) }
        }
    }

    private func compressPDFItem(_ item: CompressionItem) async {
        let wasForced = await MainActor.run { () -> Bool in
            let f = item.forceCompress
            item.forceCompress = false
            return f
        }
        let pdfOverride = await MainActor.run { () -> PDFQuality? in
            let q = item.pdfQualityOverride
            item.pdfQualityOverride = nil
            return q
        }
        let preset = activePreset(for: item)
        let urlDL = item.isURLDownloadSource
        await MainActor.run { item.status = .processing }
        let intendedOutput: URL = {
            if let pr = preset { return pr.outputURL(for: item.sourceURL, mediaType: .pdf, globalPrefs: prefs, isFromURLDownload: urlDL) }
            return prefs.outputURL(for: item.sourceURL, mediaType: .pdf, isFromURLDownload: urlDL)
        }()
        let pdfFallback = preset.map { PDFQuality(rawValue: $0.pdfQualityRaw) ?? .medium } ?? prefs.pdfQuality
        let sourceURL = item.sourceURL
        let outputMode = preset.map { PDFOutputMode(rawValue: $0.pdfOutputModeRaw) ?? .preserveStructure } ?? prefs.pdfOutputMode
        let smartQ = preset?.smartQuality ?? prefs.smartQuality
        let pdfQuality: PDFQuality
        if let o = pdfOverride, outputMode == .flattenPages {
            pdfQuality = o
        } else if outputMode == .flattenPages, smartQ {
            pdfQuality = await Task.detached {
                PDFSmartQuality.inferQuality(url: sourceURL, fallback: pdfFallback)
            }.value
        } else {
            pdfQuality = pdfFallback
        }

        let workURL: URL
        let finalURL = intendedOutput
        if sourceURL.path == finalURL.path {
            workURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("dinky_pdf_\(UUID().uuidString).pdf")
        } else {
            workURL = finalURL
        }
        let replaceOrigin = (preset.map { FilenameHandling(rawValue: $0.filenameHandlingRaw) } ?? prefs.filenameHandling) == .replaceOrigin
        let strip = preset?.stripMetadata ?? prefs.stripMetadata
        let grayscale = preset?.pdfGrayscale ?? prefs.pdfGrayscale
        var preservedModDate: Date?
        if workURL.path != finalURL.path, prefs.preserveTimestamps {
            preservedModDate = (try? FileManager.default.attributesOfItem(atPath: sourceURL.path)[.modificationDate]) as? Date
        }

        do {
            let result = try await CompressionService.shared.compressPDF(
                source: item.sourceURL,
                outputMode: outputMode,
                quality: pdfQuality,
                grayscale: grayscale,
                stripMetadata: strip,
                outputURL: workURL
            )
            let producedURL: URL
            if workURL.path != finalURL.path {
                do {
                    try FileManager.default.removeItem(at: sourceURL)
                    if FileManager.default.fileExists(atPath: finalURL.path) {
                        try FileManager.default.removeItem(at: finalURL)
                    }
                    try FileManager.default.moveItem(at: workURL, to: finalURL)
                    producedURL = finalURL
                } catch {
                    try? FileManager.default.removeItem(at: workURL)
                    await MainActor.run { item.status = .failed(error) }
                    return
                }
            } else {
                producedURL = result.outputURL
                if replaceOrigin {
                    if urlDL {
                        try? FileManager.default.removeItem(at: item.sourceURL)
                    } else {
                        try? OriginalsHandler.disposeForReplace(
                            originalAt: item.sourceURL,
                            action: prefs.originalsAction,
                            backupFolder: prefs.originalsAction == .backup ? prefs.originalsBackupDestinationURL() : nil
                        )
                    }
                }
            }

            let outSize = (try? producedURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map { Int64($0) }
                ?? result.outputSize
            let savings = result.originalSize > 0
                ? Double(result.originalSize - outSize) / Double(result.originalSize) : 0
            await MainActor.run {
                if outSize >= result.originalSize {
                    item.status = .zeroGain(attemptedSize: outSize)
                    try? FileManager.default.removeItem(at: producedURL)
                } else if self.prefs.minimumSavingsPercent > 0 && savings < Double(self.prefs.minimumSavingsPercent) / 100.0 && !wasForced {
                    item.status = .skipped(savedPercent: savings * 100, threshold: self.prefs.minimumSavingsPercent)
                    try? FileManager.default.removeItem(at: producedURL)
                } else {
                    item.status = .done(outputURL: producedURL,
                                        originalSize: result.originalSize,
                                        outputSize: outSize)
                    if self.prefs.preserveTimestamps {
                        if let d = preservedModDate {
                            try? FileManager.default.setAttributes([.modificationDate: d], ofItemAtPath: producedURL.path)
                        } else {
                            self.copyTimestamp(from: item.sourceURL, to: producedURL)
                        }
                    }
                }
            }
        } catch {
            await MainActor.run { item.status = .failed(error) }
        }
    }

    private func compressVideoItem(_ item: CompressionItem) async {
        let wasForced = await MainActor.run { () -> Bool in
            let f = item.forceCompress
            item.forceCompress = false
            return f
        }
        let videoOverride = await MainActor.run { () -> (quality: VideoQuality, codec: VideoCodecFamily)? in
            let o = item.videoRecompressOverride
            item.videoRecompressOverride = nil
            return o
        }
        let preset = activePreset(for: item)
        let urlDL = item.isURLDownloadSource
        await MainActor.run {
            item.status = .processing
            item.videoExportProgress = 0
        }
        defer { item.videoExportProgress = nil }
        let intendedOutput: URL = {
            if let pr = preset { return pr.outputURL(for: item.sourceURL, mediaType: .video, globalPrefs: prefs, isFromURLDownload: urlDL) }
            return prefs.outputURL(for: item.sourceURL, mediaType: .video, isFromURLDownload: urlDL)
        }()
        let videoFallback = preset.map { VideoQuality.resolve($0.videoQualityRaw) } ?? prefs.videoQuality
        let sourceURL = item.sourceURL
        let asset = VideoCompressor.makeURLAsset(url: sourceURL)
        let smartQ = preset?.smartQuality ?? prefs.smartQuality
        let removeAudio = preset?.videoRemoveAudio ?? prefs.videoRemoveAudio
        let codec: VideoCodecFamily
        let videoQuality: VideoQuality
        // When Smart Quality is on we also classify the clip (screen recording / camera / generic)
        // so the tier picker can adjust per content type and the results row can show what we saw.
        var smartContentType: VideoContentType? = nil
        if let o = videoOverride {
            videoQuality = o.quality
            codec = o.codec
        } else {
            codec = preset.map { VideoCodecFamily(rawValue: $0.videoCodecFamilyRaw) ?? .h264 } ?? prefs.videoCodecFamily
            if smartQ {
                let decision = await VideoSmartQuality.decide(asset: asset, fallback: videoFallback)
                videoQuality = decision.quality
                smartContentType = decision.contentType
            } else {
                videoQuality = videoFallback
            }
        }

        // User chose Smart wins: when Smart is on, ignore the resolution cap and let Smart pick the preset.
        let resolutionCap: Int?
        if smartQ {
            resolutionCap = nil
        } else {
            let capEnabled = preset?.videoMaxResolutionEnabled ?? prefs.videoMaxResolutionEnabled
            let capLines = preset?.videoMaxResolutionLines ?? prefs.videoMaxResolutionLines
            resolutionCap = capEnabled ? capLines : nil
        }

        let workURL: URL
        let finalURL = intendedOutput
        if sourceURL.path == finalURL.path {
            workURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("dinky_vid_\(UUID().uuidString).mp4")
        } else {
            workURL = finalURL
        }
        let replaceOrigin = (preset.map { FilenameHandling(rawValue: $0.filenameHandlingRaw) } ?? prefs.filenameHandling) == .replaceOrigin
        var preservedModDate: Date?
        if workURL.path != finalURL.path, prefs.preserveTimestamps {
            preservedModDate = (try? FileManager.default.attributesOfItem(atPath: sourceURL.path)[.modificationDate]) as? Date
        }

        let progressHandler: @Sendable (Float) -> Void = { p in
            Task { @MainActor in
                item.videoExportProgress = Double(p)
            }
        }

        do {
            let result = try await CompressionService.shared.compressVideo(
                asset: asset,
                source: item.sourceURL,
                quality: videoQuality,
                codec: codec,
                removeAudio: removeAudio,
                maxResolutionLines: resolutionCap,
                outputURL: workURL,
                videoContentType: smartContentType,
                progressHandler: progressHandler
            )
            let producedURL: URL
            if workURL.path != finalURL.path {
                do {
                    try FileManager.default.removeItem(at: sourceURL)
                    if FileManager.default.fileExists(atPath: finalURL.path) {
                        try FileManager.default.removeItem(at: finalURL)
                    }
                    try FileManager.default.moveItem(at: workURL, to: finalURL)
                    producedURL = finalURL
                } catch {
                    try? FileManager.default.removeItem(at: workURL)
                    await MainActor.run { item.status = .failed(error) }
                    return
                }
            } else {
                producedURL = result.outputURL
                if replaceOrigin {
                    if urlDL {
                        try? FileManager.default.removeItem(at: item.sourceURL)
                    } else {
                        try? OriginalsHandler.disposeForReplace(
                            originalAt: item.sourceURL,
                            action: prefs.originalsAction,
                            backupFolder: prefs.originalsAction == .backup ? prefs.originalsBackupDestinationURL() : nil
                        )
                    }
                }
            }

            let outSize = (try? producedURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map { Int64($0) }
                ?? result.outputSize
            let savings = result.originalSize > 0
                ? Double(result.originalSize - outSize) / Double(result.originalSize) : 0
            await MainActor.run {
                item.videoDuration = result.videoDuration
                item.detectedVideoContentType = result.videoContentType
                item.videoIsHDR = result.videoIsHDR
                if outSize >= result.originalSize {
                    item.status = .zeroGain(attemptedSize: outSize)
                    try? FileManager.default.removeItem(at: producedURL)
                } else if self.prefs.minimumSavingsPercent > 0 && savings < Double(self.prefs.minimumSavingsPercent) / 100.0 && !wasForced {
                    item.status = .skipped(savedPercent: savings * 100, threshold: self.prefs.minimumSavingsPercent)
                    try? FileManager.default.removeItem(at: producedURL)
                } else {
                    item.status = .done(outputURL: producedURL,
                                        originalSize: result.originalSize,
                                        outputSize: outSize)
                    if self.prefs.preserveTimestamps {
                        if let d = preservedModDate {
                            try? FileManager.default.setAttributes([.modificationDate: d], ofItemAtPath: producedURL.path)
                        } else {
                            self.copyTimestamp(from: item.sourceURL, to: producedURL)
                        }
                    }
                }
            }
        } catch VideoCompressionError.alreadyOptimized {
            await MainActor.run {
                item.status = .skipped(savedPercent: nil, threshold: self.prefs.minimumSavingsPercent)
            }
        } catch {
            await MainActor.run { item.status = .failed(error) }
        }
    }

    private func copyTimestamp(from source: URL, to dest: URL) {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: source.path),
              let date = attrs[.modificationDate] as? Date else { return }
        try? FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: dest.path)
    }

    private func sendNotification(count: Int, seconds: Double) {
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                postNotification(count: count, seconds: seconds)
            case .notDetermined:
                let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
                if granted { postNotification(count: count, seconds: seconds) }
            default:
                break
            }
        }
    }

    private func postNotification(count: Int, seconds: Double) {
        let types = presentMediaTypes
        let noun = types.count > 1 ? "files" : (types.first == .pdf ? "PDFs" : (types.first == .video ? "videos" : "images"))
        let body: String
        switch (count, seconds) {
        case (0, _):          body = "Done. Nothing got smaller though."
        case (1, ..<3):       body = "1 \(noun == "files" ? "file" : String(noun.dropLast())), considerably dinky-er."
        case (1, _):          body = "1 \(noun == "files" ? "file" : String(noun.dropLast())). Took a sec, worth it."
        case (2...5, ..<5):   body = "\(count) \(noun). Done before you blinked."
        case (2...5, _):      body = "\(count) \(noun), all shrunk down."
        case (6...20, ..<10): body = "\(count) \(noun) compressed. The internet will thank you."
        case (6...20, _):     body = "\(count) \(noun). Your stuff just got faster."
        default:              body = "\(count) \(noun). That's a lot — all smaller now."
        }
        let content = UNMutableNotificationContent()
        content.title = "Dinky"
        content.body = body
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req) { error in
            if let error { print("[Dinky] notification error: \(error)") }
        }
    }

    private func playCompletionSound(savedBytes: Int64) {
        let name: String
        switch savedBytes {
        case ..<102_400:   name = "Tink"  // < 100 KB
        case ..<1_048_576: name = "Pop"   // < 1 MB
        case ..<5_242_880: name = "Glass" // < 5 MB
        default:           name = "Hero"  // 5 MB+
        }
        NSSound(named: name)?.play()
    }
}

struct PNGInputError: LocalizedError {
    var errorDescription: String? {
        String(localized: "PNG lossless only works on PNG files. Try WebP or AVIF for this one.", comment: "Error when PNG output selected for non-PNG input.")
    }
}

// MARK: - Root view

struct ContentView: View {
    @EnvironmentObject var prefs: DinkyPreferences
    @EnvironmentObject var updater: UpdateChecker
    @ObservedObject private var diagnostics = DiagnosticsReporter.shared
    @Environment(\.openSettings) private var openSettings
    @ObservedObject var vm: ContentViewModel
    @StateObject private var folderWatcher = FolderWatcher()
    @State private var sidebarVisible = false
    @State private var isDropTargeted  = false
    @State private var idleLoop        = 0
    @State private var selectedIDs: Set<UUID> = []
    @State private var showingHistory  = false
    @AppStorage("manualModeHintDismissed") private var manualModeHintDismissed = false

    init(prefs: DinkyPreferences, vm: ContentViewModel) {
        self.vm = vm
        // Sync vm's prefs reference on init so it reads the shared UserDefaults instance
        vm.prefs = prefs
    }

    // Merge hover state with the vm phase so DropZoneView stays purely visual
    private var dropPhase: DropZonePhase {
        if isDropTargeted { return .hovering }
        return vm.phase
    }

    /// SwiftUI Settings scene — use this instead of `NSApp.sendAction` so the window actually opens.
    private func revealPreferences(_ tab: PreferencesTab) {
        UserDefaults.standard.set(tab.rawValue, forKey: PreferencesTab.pendingTabUserDefaultsKey)
        NotificationCenter.default.post(name: .dinkySelectPreferencesTab, object: tab.rawValue)
        openSettings()
    }

    private func handlePasteFromUser() {
        switch vm.pasteClipboard() {
        case .added: break
        case .emptyClipboard:
            showPasteAlert(title: S.pasteEmptyTitle, message: S.pasteEmptyMessage)
        case .duplicateInQueue:
            showPasteAlert(title: S.pasteDuplicateTitle, message: S.pasteDuplicateMessage)
        }
    }

    private func showPasteAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: String(localized: "OK", comment: "Alert dismiss button."))
        alert.runModal()
    }

    private var manualModeHintBanner: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "hand.tap")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(String(localized: "Manual mode: files stay queued until you right-click a row or choose Compress Now (\(prefs.shortcut(for: .compressNow).displayString)) from the File menu.", comment: "Manual mode banner; argument is shortcut."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(String(localized: "Got it", comment: "Dismiss manual mode hint.")) {
                manualModeHintDismissed = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            Button(String(localized: "Settings…", comment: "Open Settings from banner.")) {
                revealPreferences(.general)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .adaptiveGlass(in: RoundedRectangle(cornerRadius: 0, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "Manual mode is on. Files stay queued until you compress them from the row menu or File menu Compress Now, \(prefs.shortcut(for: .compressNow).displayString).", comment: "VoiceOver: manual mode banner."))
    }

    var body: some View {
        ZStack(alignment: .leading) {
            // ── Main content (drop target covers the full surface) ──
            VStack(spacing: 0) {
                if updater.shouldShow(dismissedVersion: prefs.dismissedUpdateVersion) {
                    UpdateBanner(updater: updater, itemCount: vm.items.count)
                        .environmentObject(prefs)
                }
                if prefs.manualMode && !manualModeHintDismissed {
                    manualModeHintBanner
                }
                if vm.isEmpty {
                    DropZoneView(phase: dropPhase, onOpenPanel: openPanel, onPaste: handlePasteFromUser, onLoop: { idleLoop += 1 })
                } else {
                    resultsList
                }
                bottomBar
            }
            .animation(.easeInOut(duration: 0.25), value: updater.availableVersion)
            // Drop handler lives here, above the sidebar, so the overlay can't block it
            .onDrop(of: [.fileURL, .url], isTargeted: $isDropTargeted, perform: handleDrop)

            // ── Floating sidebar (top-aligned, height = content only) ──
            if sidebarVisible {
                GeometryReader { geo in
                    VStack {
                        SidebarView(
                            selectedFormat: Binding(
                                get:  { vm.selectedFormat },
                                set:  {
                                    vm.selectedFormat = $0
                                    prefs.defaultFormat = $0
                                }
                            ),
                            openPreferences: revealPreferences
                        )
                        .environmentObject(prefs)
                        .frame(maxHeight: geo.size.height - 60)
                        Spacer()
                    }
                    .padding(12)
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .leading).combined(with: .opacity),
                    removal:   .move(edge: .leading).combined(with: .opacity)
                ))
            }
        }
        .frame(minWidth: 440, minHeight: 440)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation(.spring(duration: 0.35)) { sidebarVisible.toggle() }
                } label: {
                    Label(String(localized: "Toggle Sidebar", comment: "Toolbar: show or hide sidebar."), systemImage: "sidebar.left")
                        .symbolVariant(sidebarVisible ? .fill : .none)
                }
                .help(sidebarVisible ? String(localized: "Hide the format sidebar", comment: "Toolbar tooltip.") : String(localized: "Show the format sidebar", comment: "Toolbar tooltip."))
                .accessibilityLabel(sidebarVisible ? String(localized: "Hide format sidebar", comment: "VoiceOver.") : String(localized: "Show format sidebar", comment: "VoiceOver."))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dinkyOpenPanel)) { _ in openPanel() }
        .onReceive(NotificationCenter.default.publisher(for: .dinkyOpenFiles)) { note in
            guard let urls = note.object as? [URL] else { return }
            vm.addAndCompress(urls)
        }
        .onReceive(NotificationCenter.default.publisher(for: .dinkyPasteClipboard)) { _ in
            handlePasteFromUser()
        }
        .onReceive(NotificationCenter.default.publisher(for: .dinkyClearAll)) { _ in
            vm.clear()
            selectedIDs = []
        }
        .onReceive(NotificationCenter.default.publisher(for: .dinkyToggleSidebar)) { _ in
            withAnimation(.spring(duration: 0.35)) { sidebarVisible.toggle() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dinkyDeleteSelectedRows)) { _ in
            vm.removeSelection(with: selectedIDs)
        }
        .onReceive(NotificationCenter.default.publisher(for: .dinkyStartCompression)) { _ in
            vm.compress()
        }
        .onReceive(NotificationCenter.default.publisher(for: .dinkyShowHistory)) { _ in
            showingHistory = true
        }
        .sheet(isPresented: $showingHistory) {
            HistorySheet().environmentObject(prefs)
        }
        .onReceive(NotificationCenter.default.publisher(for: .dinkyCheckUpdates)) { _ in
            Task {
                let result = await updater.check(manual: true)
                presentManualUpdateResult(result, updater: updater)
            }
        }
        .onAppear {
            URLDownloader.sweepOldDownloads()
            prefs.reconcileSidebarSectionsForSimpleModeIfNeeded()
            updateFolderWatcher()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            updateFolderWatcher()
        }
        .task {
            await updater.check()
        }
        .onChange(of: prefs.folderWatchEnabled) { _, _ in updateFolderWatcher() }
        .onChange(of: prefs.watchedFolderPath) { _, _ in updateFolderWatcher() }
        .onChange(of: prefs.watchedFolderBookmark) { _, _ in updateFolderWatcher() }
        .onChange(of: prefs.savedPresetsData) { _, _ in updateFolderWatcher() }
        .sheet(item: $diagnostics.pendingCrashReport) { report in
            PostCrashReportSheet(report: report, diagnostics: diagnostics)
        }
    }

    // MARK: - Results list

    private var resultsList: some View {
        List(vm.items, id: \.id, selection: $selectedIDs) { item in
            ResultsRowView(
                item: item,
                selectedFormat: vm.selectedFormat,
                onForceCompress: { vm.forceCompress(item) },
                onCancelDownload: { vm.remove(item) }
            )
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.visible)
                .listRowSeparatorTint(.primary.opacity(0.08))
                .onTapGesture(count: 2) {
                    if case .downloading = item.status { return }
                    let url = item.outputURL ?? item.sourceURL
                    NSWorkspace.shared.open(url)
                }
                .onDrag {
                    if case .downloading = item.status { return NSItemProvider() }
                    let url = item.outputURL ?? item.sourceURL
                    return NSItemProvider(contentsOf: url) ?? NSItemProvider()
                }
                .contextMenu {
                    if case .processing = item.status {
                        EmptyView()
                    } else if case .downloading = item.status {
                        Button {
                            vm.remove(item)
                        } label: {
                            Label(String(localized: "Cancel Download", comment: "Context menu."), systemImage: "xmark.circle")
                        }
                    } else if case .pending = item.status {
                        let targets = selectedIDs.contains(item.id)
                            ? vm.items.filter { selectedIDs.contains($0.id) }
                            : [item]
                        if item.mediaType == .image {
                            Button { vm.compressItems(targets, format: .webp) } label: {
                                Label(String(localized: "Compress as WebP", comment: "Context menu."), systemImage: "photo")
                            }
                            Button { vm.compressItems(targets, format: .avif) } label: {
                                Label(String(localized: "Compress as AVIF", comment: "Context menu."), systemImage: "photo")
                            }
                            Button { vm.compressItems(targets, format: .png) } label: {
                                Label(String(localized: "Compress as PNG", comment: "Context menu."), systemImage: "photo")
                            }
                            Divider()
                        }
                        if item.mediaType == .pdf, vm.effectivePDFOutputMode(for: item) == .flattenPages {
                            Button { vm.queuePDFCompressAtQuality(targets, quality: .low) } label: {
                                Label(String(localized: "Compress at Low", comment: "Context menu PDF quality."), systemImage: "doc")
                            }
                            Button { vm.queuePDFCompressAtQuality(targets, quality: .medium) } label: {
                                Label(String(localized: "Compress at Medium", comment: "Context menu PDF quality."), systemImage: "doc")
                            }
                            Button { vm.queuePDFCompressAtQuality(targets, quality: .high) } label: {
                                Label(String(localized: "Compress at High", comment: "Context menu PDF quality."), systemImage: "doc")
                            }
                            Divider()
                        }
                        if item.mediaType == .video {
                            Menu {
                                Button(VideoQuality.medium.displayName) { vm.queueVideoCompress(targets, quality: .medium, codec: .h264) }
                                Button(VideoQuality.high.displayName)   { vm.queueVideoCompress(targets, quality: .high,   codec: .h264) }
                            } label: {
                                Label(String(localized: "H.264", comment: "Video codec menu."), systemImage: "film")
                            }
                            Menu {
                                Button(VideoQuality.medium.displayName) { vm.queueVideoCompress(targets, quality: .medium, codec: .hevc) }
                                Button(VideoQuality.high.displayName)   { vm.queueVideoCompress(targets, quality: .high,   codec: .hevc) }
                            } label: {
                                Label(String(localized: "H.265 (HEVC)", comment: "Video codec menu."), systemImage: "film")
                            }
                            Divider()
                        }
                    } else {
                        if case .skipped = item.status {
                            Button { vm.forceCompress(item) } label: {
                                Label(String(localized: "Compress Anyway", comment: "Context menu."), systemImage: "arrow.clockwise")
                            }
                            Divider()
                        }
                        if item.mediaType == .image {
                            Button { vm.recompress(item, as: .webp) } label: {
                                Label(String(localized: "Re-compress as WebP", comment: "Context menu."), systemImage: "photo")
                            }
                            Button { vm.recompress(item, as: .avif) } label: {
                                Label(String(localized: "Re-compress as AVIF", comment: "Context menu."), systemImage: "photo")
                            }
                            Button { vm.recompress(item, as: .png) } label: {
                                Label(String(localized: "Re-compress as PNG", comment: "Context menu."), systemImage: "photo")
                            }
                            Divider()
                        }
                        if item.mediaType == .pdf, vm.effectivePDFOutputMode(for: item) == .flattenPages {
                            Button { vm.recompressPDF(item, quality: .low) } label: {
                                Label(String(localized: "Re-compress at Low", comment: "Context menu."), systemImage: "doc")
                            }
                            Button { vm.recompressPDF(item, quality: .medium) } label: {
                                Label(String(localized: "Re-compress at Medium", comment: "Context menu."), systemImage: "doc")
                            }
                            Button { vm.recompressPDF(item, quality: .high) } label: {
                                Label(String(localized: "Re-compress at High", comment: "Context menu."), systemImage: "doc")
                            }
                            Divider()
                        }
                        if item.mediaType == .video {
                            Menu {
                                Button(VideoQuality.medium.displayName) { vm.recompressVideo(item, quality: .medium, codec: .h264) }
                                Button(VideoQuality.high.displayName)   { vm.recompressVideo(item, quality: .high,   codec: .h264) }
                            } label: {
                                Label(String(localized: "H.264", comment: "Video codec menu."), systemImage: "film")
                            }
                            Menu {
                                Button(VideoQuality.medium.displayName) { vm.recompressVideo(item, quality: .medium, codec: .hevc) }
                                Button(VideoQuality.high.displayName)   { vm.recompressVideo(item, quality: .high,   codec: .hevc) }
                            } label: {
                                Label(String(localized: "H.265 (HEVC)", comment: "Video codec menu."), systemImage: "film")
                            }
                            Divider()
                        }
                    }
                    Button {
                        vm.remove(item)
                    } label: {
                        Label(String(localized: "Remove", comment: "Context menu: remove row."), systemImage: "trash")
                    }
                    Divider()
                    Button(role: .destructive) {
                        vm.clear()
                    } label: {
                        Label(String(localized: "Clear All", comment: "Context menu: clear list."), systemImage: "trash.fill")
                    }
                }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .onChange(of: vm.isEmpty) { _, isEmpty in
            if isEmpty { selectedIDs = [] }
        }
        .onChange(of: vm.items.map(\.id)) { _, _ in
            let valid = Set(vm.items.map(\.id))
            selectedIDs = selectedIDs.filter(valid.contains)
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        ZStack {
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .animation(.easeInOut, value: vm.phase)

            HStack {
                Spacer()
                if !vm.isEmpty {
                    Button(String(localized: "Clear All", comment: "Bottom bar: clear list.")) { vm.clear() }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .adaptiveGlass(in: RoundedRectangle(cornerRadius: 0, style: .continuous))
    }

    private var statusText: String {
        switch vm.phase {
        case .idle:       return S.dropIdle(loop: idleLoop)
        case .hovering:   return S.dropHover
        case .processing: return vm.items.count >= 10 ? S.processBig : S.processBatch
        case .done:
            let skipped = vm.items.filter {
                if case .skipped  = $0.status { return true }
                if case .zeroGain = $0.status { return true }
                return false
            }.count
            let done = vm.items.filter { if case .done = $0.status { return true }; return false }.count
            return (skipped > 0 && done > 0) ? S.doneMixed : S.doneGood
        }
    }

    // MARK: - Drop handling (reliable macOS URL extraction)

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var collected: [URL] = []
        var remoteURLs: [URL] = []
        let force = NSEvent.modifierFlags.contains(.option)
        let group = DispatchGroup()
        let lock  = NSLock()

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    defer { group.leave() }
                    var resolved: URL?
                    if let url  = item as? URL  { resolved = url }
                    else if let url = item as? NSURL as URL? { resolved = url }
                    else if let data = item as? Data { resolved = URL(dataRepresentation: data, relativeTo: nil) }
                    guard let url = resolved else { return }
                    let files = expandAndFilter(url)
                    lock.lock(); collected.append(contentsOf: files); lock.unlock()
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                    defer { group.leave() }
                    let resolved: URL? = (item as? URL) ?? (item as? NSURL) as URL?
                    guard let url = resolved,
                          let scheme = url.scheme?.lowercased(),
                          scheme == "http" || scheme == "https" else { return }
                    lock.lock(); remoteURLs.append(url); lock.unlock()
                }
            }
        }

        group.notify(queue: .main) {
            if !collected.isEmpty { vm.addAndCompress(collected, force: force) }
            if !remoteURLs.isEmpty { vm.queueRemoteDownload(urls: remoteURLs, force: force) }
        }
        return true
    }

    private func expandAndFilter(_ url: URL) -> [URL] {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return [] }
        let urls: [URL] = isDir.boolValue
            ? (FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)?
                .compactMap { $0 as? URL } ?? [])
            : [url]
        return urls.filter { MediaTypeDetector.detect($0) != nil }
    }

    // MARK: - Folder watcher

    private func updateFolderWatcher() {
        prefs.reconcileFolderBookmarksIfNeeded()
        let reg = WatchPipelineRegistry(prefs: prefs)
        let paths = reg.watchedRootPaths
        guard !paths.isEmpty else {
            folderWatcher.stop()
            return
        }
        folderWatcher.onNewFiles = { urls in
            for url in urls {
                switch reg.pipeline(for: url) {
                case .global:
                    vm.addAndCompress([url], presetID: nil)
                case .preset(let id):
                    let preset = prefs.savedPresets.first(where: { $0.id == id })
                    let media = MediaTypeDetector.detect(url)
                    if let p = preset, let m = media, p.applies(to: m) {
                        vm.addAndCompress([url], presetID: id)
                    } else {
                        vm.addAndCompress([url], presetID: nil)
                    }
                }
            }
        }
        folderWatcher.start(paths: paths)
    }

    // MARK: - Open panel

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories    = true
        panel.allowedContentTypes     = [.jpeg, .png, .webP, .image, .pdf, .mpeg4Movie, .quickTimeMovie, .movie]
        if panel.runModal() == .OK {
            vm.addAndCompress(panel.urls)
        }
    }
}

// MARK: - Manual update check alerts

/// Shows a short native dialog in response to the user explicitly picking
/// `Dinky › Check for Updates…`. Automatic launch-time checks stay silent.
@MainActor
private func presentManualUpdateResult(_ result: UpdateChecker.CheckResult,
                                       updater: UpdateChecker) {
    let alert = NSAlert()
    alert.alertStyle = .informational

    switch result {
    case .updateAvailable(let version):
        alert.messageText = "A newer dinky has dropped."
        alert.informativeText = String(localized: "Version \(version) is out. You’re on \(currentAppVersion()). Want it?", comment: "Manual update alert; arguments are new and current version.")
        alert.addButton(withTitle: String(localized: "Install Update", comment: "Manual update alert."))
        alert.addButton(withTitle: String(localized: "What’s new", comment: "Manual update alert."))
        alert.addButton(withTitle: String(localized: "Maybe later", comment: "Manual update alert."))

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            Task { await updater.downloadAndInstall() }
        } else if response == .alertSecondButtonReturn, let url = updater.releaseURL {
            NSWorkspace.shared.open(url)
        }

    case .upToDate:
        alert.messageText = String(localized: "All caught up.", comment: "Manual update: no update available.")
        alert.informativeText = String(localized: "You’re on Dinky \(currentAppVersion()) — the latest and dinkyest.", comment: "Manual update: up to date; argument is version.")
        alert.addButton(withTitle: String(localized: "Nice", comment: "Dismiss up-to-date alert."))
        alert.runModal()

    case .failed:
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Couldn’t phone home.", comment: "Manual update: network error title.")
        alert.informativeText = String(localized: "Dinky couldn’t reach GitHub. Probably the internet. Try again in a sec?", comment: "Manual update: network error detail.")
        alert.addButton(withTitle: String(localized: "OK", comment: "Alert dismiss."))
        alert.runModal()
    }
}

private func currentAppVersion() -> String {
    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
}
