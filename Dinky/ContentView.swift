import SwiftUI
import DinkyPDFSignals
import UniformTypeIdentifiers
import UserNotifications
import Darwin
import AppKit
import PDFKit
import AVFoundation
import CoreMedia

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
    @Published var pendingBatchSummary: CompressionBatchSummary?
    /// Undo UI for the batch sheet (false when opened from History).
    @Published var pendingBatchSummarySupportsUndo: Bool = true
    /// Latest completed batch snapshot for **Last Batch Summary…** (menu / shortcut); cleared with **Clear All** or when no done rows remain.
    @Published var lastBatchSummary: CompressionBatchSummary?
    /// When true, `scheduleAutoClearAfterBatch` runs after the batch summary sheet is dismissed.
    private var pendingAutoClearAfterBatchSummary = false
    @Published var undoErrorMessage: String?
    /// True after the user stopped a run early; shows **Continue** to resume pending files.
    @Published var compressionInterrupted: Bool = false
    /// When manual mode is off, shows **Compress Now** after Undo from the batch sheet (undo does not auto-start a run).
    @Published var needsExplicitCompressAfterUndo: Bool = false
    private var compressionTask: Task<Void, Never>?
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
        item.undoSnapshot = nil
        item.status = .pending
        compress()
    }

    func effectivePDFOutputMode(for item: CompressionItem) -> PDFOutputMode {
        let p = item.presetID.flatMap { id in prefs.savedPresets.first(where: { $0.id == id }) }
        return p.map { PDFOutputMode(rawValue: $0.pdfOutputModeRaw) ?? .flattenPages } ?? prefs.pdfOutputMode
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
        item.undoSnapshot = nil
        item.status = .pending
        compress()
    }

    /// After a PDF zero-gain result: one-shot flatten at smallest tier (overrides preserve / sidebar mode for this item only).
    func retryPDFFlattenSmallest(_ item: CompressionItem) {
        guard item.mediaType == .pdf else { return }
        item.pdfOutputModeOverride = .flattenPages
        item.pdfQualityOverride = .smallest
        item.undoSnapshot = nil
        item.status = .pending
        compress()
    }

    /// After preserve PDF zero-gain: one-shot experimental qpdf pass; does not change flatten vs preserve.
    func retryPDFPreserveExperimental(_ item: CompressionItem, mode: PDFPreserveExperimentalMode) {
        guard item.mediaType == .pdf else { return }
        item.pdfPreserveExperimentalOverride = mode
        item.undoSnapshot = nil
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
        item.undoSnapshot = nil
        item.status = .pending
        compress()
    }

    func forceCompress(_ item: CompressionItem) {
        item.forceCompress = true
        item.undoSnapshot = nil
        item.status = .pending
        compress()
    }

    func undoCompression(_ item: CompressionItem) {
        guard let snap = item.undoSnapshot else { return }
        do {
            try CompressionUndo.undo(snapshot: snap)
            item.undoSnapshot = nil
            item.status = .pending
            refreshPendingBatchSummaryIfNeeded()
            syncExplicitCompressCueAfterUndo()
        } catch {
            undoErrorMessage = error.localizedDescription
        }
    }

    /// After undo from the batch sheet, pending work does not auto-run when manual mode is off — surface **Compress Now**.
    private func syncExplicitCompressCueAfterUndo() {
        guard !prefs.manualMode else { return }
        let hasPending = items.contains { if case .pending = $0.status { return true }; return false }
        if hasPending { needsExplicitCompressAfterUndo = true }
    }

    /// Rebuilds file rows and byte totals from the current queue while preserving batch metadata and stable summary id.
    private func reconciledBatchSummary(from existing: CompressionBatchSummary) -> CompressionBatchSummary {
        let fileRows = BatchSummaryListRow.rows(from: items)
        let doneCount = items.filter { if case .done = $0.status { return true }; return false }.count
        let skippedCount = items.filter { if case .skipped = $0.status { return true }; return false }.count
        let undoableDoneCount = items.filter { i in
            guard case .done = i.status else { return false }
            return i.undoSnapshot != nil
        }.count
        let savedBytes = items.reduce(Int64(0)) { $0 + $1.savedBytes }
        let pdfOCRAppliedCount = items.filter { i in
            guard i.mediaType == .pdf, case .done = i.status else { return false }
            return i.lastPdfCompressionOCRApplied
        }.count
        let outputFolderURL = fileRows.compactMap { row -> URL? in
            if case .compressed(let r) = row { return URL(fileURLWithPath: r.outputPath).deletingLastPathComponent() }
            return nil
        }.first ?? existing.outputFolderURL
        return CompressionBatchSummary(
            id: existing.id,
            savedBytes: savedBytes,
            doneCount: doneCount,
            elapsed: existing.elapsed,
            openedFolder: existing.openedFolder,
            skippedCount: skippedCount,
            outputFolderURL: outputFolderURL,
            fileRows: fileRows,
            undoableDoneCount: undoableDoneCount,
            pdfOCRAppliedCount: pdfOCRAppliedCount
        )
    }

    /// Keeps the batch summary sheet in sync after a single-item undo (stable summary `id` preserves the open sheet).
    private func refreshPendingBatchSummaryIfNeeded() {
        guard let existing = pendingBatchSummary else { return }
        let updated = reconciledBatchSummary(from: existing)
        pendingBatchSummary = updated
        lastBatchSummary = updated
    }

    /// Presents the last completed batch summary again (menu / shortcut), reconciling undo state with the current queue.
    func showLastBatchSummary() {
        guard let base = lastBatchSummary else { return }
        let updated = reconciledBatchSummary(from: base)
        lastBatchSummary = updated
        pendingBatchSummary = updated
        pendingBatchSummarySupportsUndo = true
    }

    /// Opens a saved snapshot from History (read-only; no undo).
    func presentHistoricalBatchSummary(_ summary: CompressionBatchSummary) {
        pendingBatchSummary = summary
        pendingBatchSummarySupportsUndo = false
    }

    /// Undoes all completed items that still have an undo snapshot (reverse queue order).
    func undoAllCompressibleDone() {
        let targets = items.filter { item in
            guard case .done = item.status else { return false }
            return item.undoSnapshot != nil
        }
        for item in targets.reversed() {
            guard let snap = item.undoSnapshot else { continue }
            do {
                try CompressionUndo.undo(snapshot: snap)
                item.undoSnapshot = nil
                item.status = .pending
            } catch {
                undoErrorMessage = error.localizedDescription
                return
            }
        }
        if !items.contains(where: { if case .done = $0.status { return true }; return false }) {
            lastBatchSummary = nil
        } else if let s = lastBatchSummary {
            lastBatchSummary = reconciledBatchSummary(from: s)
        }
        if !items.isEmpty, items.allSatisfy({ if case .pending = $0.status { return true }; return false }) {
            phase = .idle
        }
        syncExplicitCompressCueAfterUndo()
    }

    func onBatchSummaryDismissed() {
        guard pendingAutoClearAfterBatchSummary else { return }
        pendingAutoClearAfterBatchSummary = false
        scheduleAutoClearAfterBatch()
    }

    func clear() {
        compressionTask?.cancel()
        compressionTask = nil
        cleanupPasteTemps(for: items)
        items = []
        phase = .idle
        isProcessing = false
        compressionInterrupted = false
        lastBatchSummary = nil
        pendingBatchSummarySupportsUndo = true
        needsExplicitCompressAfterUndo = false
    }

    /// Cancels the in-flight batch. Remaining queued work stays **pending**; use **Continue** to resume.
    func stopCompression() {
        compressionTask?.cancel()
    }

    func remove(_ item: CompressionItem) {
        item.downloadTask?.cancel()
        item.downloadTask = nil
        cleanupPasteTemps(for: [item])
        items.removeAll { $0.id == item.id }
        if items.isEmpty { phase = .idle }
    }

    /// Download remote `http(s)` media URLs (max 4 concurrent), then queue for compression.
    func queueRemoteDownload(urls: [URL], force: Bool, presetID: UUID? = nil) {
        for url in urls {
            let placeholder = FileManager.default.temporaryDirectory
                .appendingPathComponent("dinky_dl_placeholder_\(UUID().uuidString)")
            let item = CompressionItem(sourceURL: placeholder, presetID: presetID, mediaType: .image)
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
        compressionInterrupted = false
        needsExplicitCompressAfterUndo = false
        var pending = items.filter { if case .pending = $0.status { return true }; return false }
        if prefs.batchLargestFirst {
            pending.sort { $0.originalSize > $1.originalSize }
        }
        // Nothing to do — don't flicker the drop zone into a `.done` "All done!"
        // screen when the user fires Compress Now with an empty queue.
        guard !pending.isEmpty else { return }
        isProcessing = true
        phase = .processing
        compressionStartTime = .now

        let batchPreset = batchSharedPreset(from: pending)

        compressionTask = Task { [weak self] in
            guard let self else { return }
            await withTaskGroup(of: Void.self) { group in
                let mediaSem = AsyncSemaphore(limit: self.prefs.concurrentCompressionLimit)
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
            let batchCancelled = Task.isCancelled
            await MainActor.run {
                self.compressionTask = nil
                self.isProcessing = false
                if self.items.isEmpty {
                    self.phase = .idle
                    self.compressionInterrupted = false
                    return
                }
                if batchCancelled {
                    for i in self.items.indices {
                        if case .processing = self.items[i].status {
                            self.items[i].status = .pending
                        }
                    }
                    let hasFinishedWork = self.items.contains { item in
                        switch item.status {
                        case .done, .skipped, .zeroGain, .failed: return true
                        default: return false
                        }
                    }
                    self.phase = hasFinishedWork ? .done : .idle
                    self.compressionInterrupted = true
                    return
                }
                self.compressionInterrupted = false
                // If the queue was emptied mid-run (Clear All, autoClear race, etc.),
                // don't strand the empty drop zone in `.done` — fall back to idle.
                self.phase = self.items.isEmpty ? .idle : .done
                let batchSaved = self.items.reduce(Int64(0)) { $0 + $1.savedBytes }
                self.prefs.lifetimeSavedBytes += batchSaved

                let doneCount = self.items.filter { if case .done = $0.status { return true }; return false }.count

                let elapsed = Date.now.timeIntervalSince(self.compressionStartTime)
                let doneItems = self.items.compactMap { item -> URL? in
                    if case .done(let url, _, _) = item.status { return url } else { return nil }
                }
                let outputFolderURL = doneItems.first?.deletingLastPathComponent()

                let openFolder = batchPreset?.openFolderWhenDone ?? self.prefs.openFolderWhenDone
                if openFolder, let first = doneItems.first {
                    NSWorkspace.shared.open(first.deletingLastPathComponent())
                }

                let hasTerminalForSummary = self.items.contains { item in
                    switch item.status {
                    case .done, .skipped, .zeroGain, .failed: return true
                    default: return false
                    }
                }

                if hasTerminalForSummary {
                    let skippedCount = self.items.filter { if case .skipped = $0.status { return true }; return false }.count
                    let openedFolder = openFolder && outputFolderURL != nil
                    let fileRows = BatchSummaryListRow.rows(from: self.items)
                    let summaryOutputFolder = fileRows.compactMap { row -> URL? in
                        if case .compressed(let r) = row {
                            return URL(fileURLWithPath: r.outputPath).deletingLastPathComponent()
                        }
                        return nil
                    }.first ?? outputFolderURL
                    let undoableDoneCount = self.items.filter { i in
                        guard case .done = i.status else { return false }
                        return i.undoSnapshot != nil
                    }.count
                    let pdfOCRAppliedCount = self.items.filter { i in
                        guard i.mediaType == .pdf, case .done = i.status else { return false }
                        return i.lastPdfCompressionOCRApplied
                    }.count
                    let summary = CompressionBatchSummary(
                        id: UUID(),
                        savedBytes: batchSaved,
                        doneCount: doneCount,
                        elapsed: elapsed,
                        openedFolder: openedFolder,
                        skippedCount: skippedCount,
                        outputFolderURL: summaryOutputFolder,
                        fileRows: fileRows,
                        undoableDoneCount: undoableDoneCount,
                        pdfOCRAppliedCount: pdfOCRAppliedCount
                    )
                    self.lastBatchSummary = summary
                    let batchSummaryData = try? JSONEncoder().encode(summary)
                    let formats = Array(Set(self.items.compactMap { item -> String? in
                        guard case .done = item.status else { return nil }
                        switch item.mediaType {
                        case .image: return (item.formatOverride ?? self.selectedFormat).displayName
                        case .pdf:   return "PDF"
                        case .video: return "Video"
                        }
                    })).sorted()
                    let record = SessionRecord(
                        id: UUID(),
                        timestamp: .now,
                        fileCount: fileRows.count,
                        totalBytesSaved: batchSaved,
                        formats: formats,
                        batchSummaryData: batchSummaryData
                    )
                    var history = self.prefs.sessionHistory
                    history.insert(record, at: 0)
                    self.prefs.sessionHistory = Array(history.prefix(50))

                    if self.prefs.showBatchSummaryDialog {
                        self.pendingBatchSummary = summary
                        self.pendingBatchSummarySupportsUndo = true
                    }
                }

                if self.prefs.playSoundEffects { self.playCompletionSound(savedBytes: batchSaved) }

                let notify = batchPreset?.notifyWhenDone ?? self.prefs.notifyWhenDone
                if notify {
                    self.sendNotification(count: doneItems.count, seconds: elapsed)
                }

                if self.prefs.autoClearWhenDone, doneItems.isEmpty == false {
                    if self.prefs.showBatchSummaryDialog, hasTerminalForSummary {
                        self.pendingAutoClearAfterBatchSummary = true
                    } else {
                        self.scheduleAutoClearAfterBatch()
                    }
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

    private func collisionNamingStyle(for item: CompressionItem) -> CollisionNamingStyle {
        if let p = activePreset(for: item) {
            return CollisionNamingStyle(rawValue: p.collisionNamingStyleRaw) ?? .finderDuplicate
        }
        return prefs.collisionNamingStyle
    }

    private func collisionCustomPattern(for item: CompressionItem) -> String {
        if let p = activePreset(for: item) {
            return p.collisionCustomPattern
        }
        return prefs.collisionCustomPattern
    }

    private func compressItem(_ item: CompressionItem) async {
        if Task.isCancelled { return }
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
        let sourceSnapshot = item.sourceURL
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

        var classifiedForResolver: ContentType? = nil
        var preclassifiedForSmartQ: ContentType? = nil
        if autoFmt, item.formatOverride == nil {
            let ct = ContentClassifier.classify(item.sourceURL)
            classifiedForResolver = ct
            await MainActor.run { item.detectedContentType = ct }
            if smartQ { preclassifiedForSmartQ = ct }
        } else if smartQ {
            let ct = ContentClassifier.classify(item.sourceURL)
            classifiedForResolver = ct
            await MainActor.run { item.detectedContentType = ct }
            preclassifiedForSmartQ = ct
        }

        let format = ImageCompressionFormatResolver.resolvedFormat(
            sourceURL: item.sourceURL,
            formatOverride: item.formatOverride,
            preset: preset,
            globalAutoFormat: prefs.autoFormat,
            globalSelectedFormat: selectedFormat,
            classifiedContent: classifiedForResolver
        )

        let srcExt = item.sourceURL.pathExtension.lowercased()
        let pngSourceOK = srcExt == "png" || srcExt == "heic" || srcExt == "heif"
        if format == .png && !pngSourceOK {
            await MainActor.run { item.status = .failed(PNGInputError()) }
            return
        }

        await MainActor.run {
            item.usedFirstFrameOnly = false
            item.status = .processing
            item.compressionProgress = 0
        }
        defer { item.compressionProgress = nil }
        let urlDL = item.isURLDownloadSource
        let outputURL: URL = {
            if let pr = preset { return pr.outputURL(for: item.sourceURL, format: format, globalPrefs: prefs, isFromURLDownload: urlDL) }
            return prefs.outputURL(for: item.sourceURL, format: format, isFromURLDownload: urlDL)
        }()
        let replaceOrigin = (preset.map { FilenameHandling(rawValue: $0.filenameHandlingRaw) } ?? prefs.filenameHandling) == .replaceOrigin
        let backupURL = prefs.originalsAction == .backup ? prefs.originalsBackupDestinationURL() : nil
        CompressionTiming.logReproContext(
            media: "image",
            smartQuality: smartQ,
            extra: "autoFormat=\(autoFmt) format=\(format.rawValue) concurrent=\(prefs.concurrentCompressionLimit) maxWidth=\(goals.maxWidth != nil) maxFileSizeKB=\(goals.maxFileSizeKB != nil)"
        )
        let progressHandler: @Sendable (Float) -> Void = { p in
            Task { @MainActor in
                item.compressionProgress = Double(p)
            }
        }
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
                preclassifiedContent: preclassifiedForSmartQ,
                parallelCompressionLimit: prefs.concurrentCompressionLimit,
                collisionNamingStyle: collisionNamingStyle(for: item),
                collisionCustomPattern: collisionCustomPattern(for: item),
                progressHandler: progressHandler
            )
            let savings = result.originalSize > 0
                ? Double(result.originalSize - result.outputSize) / Double(result.originalSize) : 0
            await MainActor.run {
                item.usedFirstFrameOnly = result.usedFirstFrameOnly
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
                        self.copyTimestamp(from: sourceSnapshot, to: result.outputURL)
                    }
                    self.copyFinderCommentsIfSettingsAllow(from: sourceSnapshot, to: result.outputURL)
                    var mergedRecovery = result.originalRecoveryURL
                    if replaceOrigin {
                        if urlDL {
                            try? FileManager.default.removeItem(at: item.sourceURL)
                        } else if let r2 = try? OriginalsHandler.disposeForReplace(
                            originalAt: item.sourceURL,
                            outputURL: result.outputURL,
                            action: self.prefs.originalsAction,
                            backupFolder: self.prefs.originalsAction == .backup ? self.prefs.originalsBackupDestinationURL() : nil
                        ) {
                            mergedRecovery = r2
                        }
                    }
                    item.undoSnapshot = CompressionUndoSnapshot(
                        sourceURL: sourceSnapshot,
                        outputURL: result.outputURL,
                        originalRecoveryURL: mergedRecovery,
                        replaceOriginal: replaceOrigin,
                        isURLDownloadSource: urlDL
                    )
                }
            }
        } catch {
            await MainActor.run { item.status = .failed(error) }
        }
    }

    private func compressPDFItem(_ item: CompressionItem) async {
        await MainActor.run {
            item.forceCompress = false
        }
        let (pdfOverride, pdfModeOverride, pdfExperimentalOverride) = await MainActor.run { () -> (PDFQuality?, PDFOutputMode?, PDFPreserveExperimentalMode?) in
            let q = item.pdfQualityOverride
            item.pdfQualityOverride = nil
            let m = item.pdfOutputModeOverride
            item.pdfOutputModeOverride = nil
            let e = item.pdfPreserveExperimentalOverride
            item.pdfPreserveExperimentalOverride = nil
            return (q, m, e)
        }
        let preset = activePreset(for: item)
        let urlDL = item.isURLDownloadSource
        await MainActor.run {
            item.status = .processing
            item.compressionProgress = 0
            item.zeroGainPDFOutputMode = nil
            if item.pageCount == nil {
                item.pageCount = PDFDocument(url: item.sourceURL)?.pageCount
            }
        }
        var ocrTempURL: URL?
        defer {
            item.compressionProgress = nil
            item.compressionStageLabel = nil
            if let t = ocrTempURL { try? FileManager.default.removeItem(at: t) }
        }
        let intendedOutput: URL = {
            if let pr = preset { return pr.outputURL(for: item.sourceURL, mediaType: .pdf, globalPrefs: prefs, isFromURLDownload: urlDL) }
            return prefs.outputURL(for: item.sourceURL, mediaType: .pdf, isFromURLDownload: urlDL)
        }()
        let pdfFallback = preset.map { PDFQuality(rawValue: $0.pdfQualityRaw) ?? .medium } ?? prefs.pdfQuality
        let sourceURL = item.sourceURL
        let outputMode = pdfModeOverride ?? preset.map { PDFOutputMode(rawValue: $0.pdfOutputModeRaw) ?? .flattenPages } ?? prefs.pdfOutputMode
        let smartQ = preset?.smartQuality ?? prefs.smartQuality
        var monoLikelihoodForFlatten: Double = 0
        let pdfQuality: PDFQuality
        let autoMonoScans = preset?.pdfAutoGrayscaleMonoScans ?? prefs.pdfAutoGrayscaleMonoScans
        if let o = pdfOverride, outputMode == .flattenPages {
            pdfQuality = o
        } else if outputMode == .flattenPages, smartQ {
            let tInfer = CFAbsoluteTimeGetCurrent()
            let (q, mono) = await Task.detached {
                PDFSmartQuality.inferFlattenQualityAndMono(
                    url: sourceURL,
                    fallback: pdfFallback,
                    autoGrayscaleMonoScans: autoMonoScans
                )
            }.value
            pdfQuality = q
            monoLikelihoodForFlatten = mono
            CompressionTiming.logPhase("pdf.smartQuality.infer", startedAt: tInfer)
        } else {
            pdfQuality = pdfFallback
        }

        let pdfOCREnabled = preset?.pdfEnableOCR ?? prefs.pdfEnableOCR
        let pdfOCRLangs = preset?.pdfOCRLanguages ?? prefs.pdfOCRLanguages
        var sourceForCompression = sourceURL

        await MainActor.run {
            item.lastPdfCompressionOCROptIn = pdfOCREnabled
            item.lastPdfCompressionOCRApplied = false
        }

        if pdfOCREnabled {
            let likelihood = await Task.detached {
                PDFDocumentSampler.sample(url: sourceURL)?.scanLikelihood ?? 0
            }.value
            if likelihood >= PDFScanDetection.ocrLikelihoodThreshold {
                let tmp = FileManager.default.temporaryDirectory
                    .appendingPathComponent("dinky_ocr_\(UUID().uuidString).pdf")
                do {
                    try await PDFOCRService.makeSearchableCopy(
                        sourceURL: sourceURL,
                        outputURL: tmp,
                        languages: pdfOCRLangs,
                        progressHandler: { done, total in
                            Task { @MainActor in
                                item.compressionStageLabel = String.localizedStringWithFormat(
                                    String(localized: "OCR page %lld of %lld", comment: "PDF OCR progress; page X of Y."),
                                    Int64(done), Int64(total)
                                )
                                let frac = Double(done) / Double(max(total, 1))
                                item.compressionProgress = frac * 0.2
                            }
                        }
                    )
                    ocrTempURL = tmp
                    sourceForCompression = tmp
                    await MainActor.run { item.lastPdfCompressionOCRApplied = true }
                } catch {
                    // Use the original file when OCR fails.
                }
            }
        }

        let preserveQpdfSteps: [PDFPreserveQpdfStep] = {
            guard outputMode == .preserveStructure else { return [.base] }
            if let o = pdfExperimentalOverride {
                return [PDFPreserveQpdfStep.from(experimental: o)]
            }
            let exp = preset.map { PDFPreserveExperimentalMode(rawValue: $0.pdfPreserveExperimentalRaw) ?? .none }
                ?? prefs.pdfPreserveExperimental
            return PDFPreserveQpdfStepsResolver.steps(
                sourceURL: sourceForCompression,
                preserveExperimental: exp,
                smartQuality: smartQ
            )
        }()

        CompressionTiming.logReproContext(
            media: "pdf",
            smartQuality: smartQ,
            extra: "mode=\(outputMode.rawValue) flatten=\(outputMode == .flattenPages)"
        )

        let collisionStyle = collisionNamingStyle(for: item)
        let finalURL = OutputPathUniqueness.uniqueOutputURL(
            desired: intendedOutput,
            sourceURL: sourceURL,
            style: collisionStyle,
            customPattern: collisionCustomPattern(for: item)
        )
        let workURL: URL
        if sourceURL.path == finalURL.path {
            workURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("dinky_pdf_\(UUID().uuidString).pdf")
        } else {
            workURL = finalURL
        }
        let replaceOrigin = (preset.map { FilenameHandling(rawValue: $0.filenameHandlingRaw) } ?? prefs.filenameHandling) == .replaceOrigin
        let strip = preset?.stripMetadata ?? prefs.stripMetadata
        let grayscalePref = preset?.pdfGrayscale ?? prefs.pdfGrayscale
        let pdfMaxFSEnabled = preset?.pdfMaxFileSizeEnabled ?? prefs.pdfMaxFileSizeEnabled
        let pdfTargetBytes: Int64? = pdfMaxFSEnabled
            ? Int64((preset?.pdfMaxFileSizeKB ?? prefs.pdfMaxFileSizeKB) * 1024)
            : nil
        let pdfResolutionDownsampling = outputMode == .preserveStructure
            && (preset?.pdfResolutionDownsampling ?? prefs.pdfResolutionDownsampling)
        let effectiveGrayscale: Bool = {
            guard outputMode == .flattenPages else { return grayscalePref }
            if grayscalePref { return true }
            if smartQ, autoMonoScans, monoLikelihoodForFlatten >= 0.5 { return true }
            return false
        }()
        var preservedModDate: Date?
        if workURL.path != finalURL.path, prefs.preserveTimestamps {
            preservedModDate = (try? FileManager.default.attributesOfItem(atPath: sourceURL.path)[.modificationDate]) as? Date
        }

        let ocrPhaseFraction: Double = (ocrTempURL != nil) ? 0.2 : 0
        let pdfProgress: @Sendable (Float) -> Void = { p in
            Task { @MainActor in
                item.compressionStageLabel = nil
                item.compressionProgress = ocrPhaseFraction + Double(p) * (1.0 - ocrPhaseFraction)
            }
        }
        let qualityAttempts: [PDFQuality] = outputMode == .flattenPages
            ? PDFQuality.flattenQualityFallbackChain(startingAt: pdfQuality)
            : [pdfQuality]

        do {
            var chosenResult: CompressionResult?
            var chosenOutSize: Int64 = 0
            var lastAttemptedOutSize: Int64 = 0

            for q in qualityAttempts {
                let result = try await CompressionService.shared.compressPDF(
                    source: sourceForCompression,
                    outputMode: outputMode,
                    quality: q,
                    grayscale: effectiveGrayscale,
                    stripMetadata: strip,
                    outputURL: workURL,
                    preserveQpdfSteps: preserveQpdfSteps,
                    targetBytes: pdfTargetBytes,
                    resolutionDownsampling: pdfResolutionDownsampling,
                    collisionNamingStyle: collisionStyle,
                    collisionCustomPattern: collisionCustomPattern(for: item),
                    progressHandler: pdfProgress
                )
                let outSize = (try? workURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map { Int64($0) }
                    ?? result.outputSize
                lastAttemptedOutSize = outSize
                if outSize >= result.originalSize {
                    continue
                }
                // Any smaller output counts for PDF — “Skip if savings below” is for images/video only (PDF wins are often small but real on preserve, or meaningful on flatten).
                if chosenResult == nil || outSize < chosenOutSize {
                    chosenResult = result
                    chosenOutSize = outSize
                }
                // Without a size target, first improvement is good enough.
                // With a target, keep stepping down quality until we're under it.
                let targetMet = pdfTargetBytes.map { outSize <= $0 } ?? true
                if targetMet { break }
            }

            if chosenResult == nil, outputMode == .flattenPages {
                // Never force grayscale for bailouts — only the user’s “Grayscale PDFs” setting applies.
                let bailouts: [(lastResort: Bool, ultra: Bool)] = [
                    (true, false),
                    (false, true),
                ]
                for pass in bailouts {
                    // With a size target: continue even after a successful result if not under target yet.
                    let bailoutTargetMet = pdfTargetBytes.map { (chosenOutSize) <= $0 } ?? false
                    guard chosenResult == nil || (!bailoutTargetMet && pdfTargetBytes != nil) else { break }
                    do {
                        let lr = try await CompressionService.shared.compressPDF(
                            source: sourceForCompression,
                            outputMode: outputMode,
                            quality: pdfQuality,
                            grayscale: effectiveGrayscale,
                            stripMetadata: strip,
                            outputURL: workURL,
                            flattenLastResort: pass.lastResort,
                            flattenUltra: pass.ultra,
                            preserveQpdfSteps: preserveQpdfSteps,
                            collisionNamingStyle: collisionStyle,
                            collisionCustomPattern: collisionCustomPattern(for: item),
                            progressHandler: pdfProgress
                        )
                        let outSize = (try? workURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map { Int64($0) }
                            ?? lr.outputSize
                        lastAttemptedOutSize = outSize
                        if outSize < lr.originalSize, chosenResult == nil || outSize < chosenOutSize {
                            chosenResult = lr
                            chosenOutSize = outSize
                        }
                    } catch {
                        // Bailout flatten failed — try next pass or fall through to zero-gain.
                    }
                }
            }

            guard let result = chosenResult else {
                let originalBytesForLog: Int64 = (try? item.sourceURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map { Int64($0) }
                    ?? ((try? FileManager.default.attributesOfItem(atPath: item.sourceURL.path)[.size] as? NSNumber)?.int64Value ?? 0)
                PDFCompressionMetrics.logRejectedOutput(
                    outputMode: outputMode,
                    originalBytes: max(originalBytesForLog, 1),
                    attemptedBytes: lastAttemptedOutSize,
                    reason: "zero_gain_no_smaller_output"
                )
                try? FileManager.default.removeItem(at: workURL)
                await MainActor.run {
                    item.zeroGainPDFOutputMode = outputMode
                    item.status = .zeroGain(attemptedSize: lastAttemptedOutSize)
                }
                return
            }

            let producedURL: URL
            var recoveryForUndo: URL?
            if workURL.path != finalURL.path {
                do {
                    recoveryForUndo = try? OriginalsHandler.disposeSourceBeforeTempSwap(
                        originalAt: sourceURL,
                        action: prefs.originalsAction,
                        backupFolder: prefs.originalsAction == .backup ? prefs.originalsBackupDestinationURL() : nil
                    )
                    producedURL = try OutputPathUniqueness.moveTempItemToUniqueOutput(
                        temp: workURL,
                        desiredOutput: finalURL,
                        sourceURL: sourceURL,
                        style: collisionStyle,
                        customPattern: collisionCustomPattern(for: item)
                    )
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
                        recoveryForUndo = try? OriginalsHandler.disposeForReplace(
                            originalAt: item.sourceURL,
                            outputURL: producedURL,
                            action: prefs.originalsAction,
                            backupFolder: prefs.originalsAction == .backup ? prefs.originalsBackupDestinationURL() : nil
                        )
                    }
                }
            }

            let outSize = (try? producedURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map { Int64($0) }
                ?? chosenOutSize
            await MainActor.run {
                item.status = .done(outputURL: producedURL,
                                    originalSize: result.originalSize,
                                    outputSize: outSize)
                if self.prefs.preserveTimestamps {
                    if let d = preservedModDate {
                        try? FileManager.default.setAttributes([.modificationDate: d], ofItemAtPath: producedURL.path)
                    } else {
                        self.copyTimestamp(from: sourceURL, to: producedURL)
                    }
                }
                self.copyFinderCommentsIfSettingsAllow(from: sourceURL, to: producedURL)
                item.undoSnapshot = CompressionUndoSnapshot(
                    sourceURL: sourceURL,
                    outputURL: producedURL,
                    originalRecoveryURL: recoveryForUndo,
                    replaceOriginal: replaceOrigin,
                    isURLDownloadSource: urlDL
                )
            }
        } catch let pdfErr as PDFCompressionError {
            if case .rewriteNotSmallerThanOriginal(let attempted) = pdfErr {
                try? FileManager.default.removeItem(at: workURL)
                await MainActor.run {
                    item.zeroGainPDFOutputMode = outputMode
                    item.status = .zeroGain(attemptedSize: attempted)
                }
            } else {
                await MainActor.run { item.status = .failed(pdfErr) }
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
            item.compressionProgress = 0
        }
        defer { item.compressionProgress = nil }
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
        var hdrFromSmartQuality = false
        if let o = videoOverride {
            videoQuality = o.quality
            codec = o.codec
        } else {
            codec = preset.map { VideoCodecFamily(rawValue: $0.videoCodecFamilyRaw) ?? .h264 } ?? prefs.videoCodecFamily
            if smartQ {
                let decision = await VideoSmartQuality.decide(asset: asset, fallback: videoFallback)
                videoQuality = decision.quality
                smartContentType = decision.contentType
                hdrFromSmartQuality = decision.isHDR
            } else {
                videoQuality = videoFallback
            }
        }

        // Classification + duration (and HDR when Smart Quality ran) before encoding so rows still show chips if export fails.
        let durationSeconds: Double?
        do {
            let d = try await asset.load(.duration)
            let secs = CMTimeGetSeconds(d)
            durationSeconds = secs.isFinite && secs > 0 ? secs : nil
        } catch {
            durationSeconds = nil
        }
        await MainActor.run {
            item.detectedVideoContentType = smartContentType
            if smartQ {
                item.videoIsHDR = hdrFromSmartQuality
            }
            if let s = durationSeconds {
                item.videoDuration = s
            }
        }

        // Max resolution cap applies whenever enabled — Smart Quality still picks Balanced / High; the cap limits export preset height.
        let capEnabled = preset?.videoMaxResolutionEnabled ?? prefs.videoMaxResolutionEnabled
        let capLines = preset?.videoMaxResolutionLines ?? prefs.videoMaxResolutionLines
        let resolutionCap: Int? = capEnabled ? capLines : nil
        CompressionTiming.logReproContext(
            media: "video",
            smartQuality: smartQ,
            extra: "cap=\(resolutionCap.map(String.init) ?? "off") codec=\(codec.rawValue)"
        )

        let collisionStyle = collisionNamingStyle(for: item)
        let finalURL = OutputPathUniqueness.uniqueOutputURL(
            desired: intendedOutput,
            sourceURL: sourceURL,
            style: collisionStyle,
            customPattern: collisionCustomPattern(for: item)
        )
        let workURL: URL
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
                item.compressionProgress = Double(p)
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
            var recoveryForUndo: URL?
            if workURL.path != finalURL.path {
                do {
                    recoveryForUndo = try? OriginalsHandler.disposeSourceBeforeTempSwap(
                        originalAt: sourceURL,
                        action: prefs.originalsAction,
                        backupFolder: prefs.originalsAction == .backup ? prefs.originalsBackupDestinationURL() : nil
                    )
                    producedURL = try OutputPathUniqueness.moveTempItemToUniqueOutput(
                        temp: workURL,
                        desiredOutput: finalURL,
                        sourceURL: sourceURL,
                        style: collisionStyle,
                        customPattern: collisionCustomPattern(for: item)
                    )
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
                        recoveryForUndo = try? OriginalsHandler.disposeForReplace(
                            originalAt: item.sourceURL,
                            outputURL: producedURL,
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
                            self.copyTimestamp(from: sourceURL, to: producedURL)
                        }
                    }
                    self.copyFinderCommentsIfSettingsAllow(from: sourceURL, to: producedURL)
                    item.undoSnapshot = CompressionUndoSnapshot(
                        sourceURL: sourceURL,
                        outputURL: producedURL,
                        originalRecoveryURL: recoveryForUndo,
                        replaceOriginal: replaceOrigin,
                        isURLDownloadSource: urlDL
                    )
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

    private func copyFinderCommentsIfSettingsAllow(from source: URL, to destination: URL) {
        guard prefs.preserveFinderComments else { return }
        FinderCommentsCopier.copyFinderComment(from: source, to: destination)
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
        String(localized: "PNG lossless only works on PNG, HEIC, or HEIF files. Try WebP or AVIF for other images.", comment: "Error when PNG output selected for unsupported input.")
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
    @AppStorage("reviewPromptBelowUpdateDismissed") private var reviewPromptBelowUpdateDismissed = false
    /// Stacked over the batch summary sheet when the user opens skipped / zero-gain / error detail from the summary list.
    @State private var batchSummaryFollowUp: BatchSummaryFollowUpSheet?
    /// First-run (or “always confirm”) sheet before user-initiated files enter the queue.
    @State private var pendingCompressionConfirmation: PendingCompressionConfirmation?

    private enum BatchSummaryFollowUpSheet: Identifiable {
        case zeroGain(itemId: UUID, filename: String, originalSize: Int64, attemptedSize: Int64, isPDF: Bool, pdfOutputMode: PDFOutputMode?)
        case failed(itemId: UUID, filename: String, error: Error)

        var id: UUID {
            switch self {
            case .zeroGain(let itemId, _, _, _, _, _): return itemId
            case .failed(let itemId, _, _): return itemId
            }
        }
    }

    init(prefs: DinkyPreferences, vm: ContentViewModel) {
        self.vm = vm
        // Sync vm's prefs reference on init so it reads the shared UserDefaults instance
        vm.prefs = prefs
    }

    private var pendingItemCount: Int {
        vm.items.filter { if case .pending = $0.status { return true }; return false }.count
    }

    /// Primary CTA for manual mode — matches File ▸ Compress Now (hidden while **Continue** is shown).
    private var showCompressNowCTA: Bool {
        (prefs.manualMode || vm.needsExplicitCompressAfterUndo)
            && pendingItemCount > 0
            && !vm.isProcessing
            && !vm.compressionInterrupted
    }

    /// After **Stop**, resume the remaining pending files (auto or manual).
    private var showContinueCTA: Bool {
        vm.compressionInterrupted && pendingItemCount > 0 && !vm.isProcessing
    }

    private func toggleSidebarVisible() {
        withAnimation(.spring(duration: 0.35)) {
            sidebarVisible.toggle()
        }
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
        guard let imp = ClipboardImporter.importFromClipboard() else {
            showPasteAlert(title: S.pasteEmptyTitle, message: S.pasteEmptyMessage)
            return
        }
        switch imp {
        case .localFile(let url):
            if vm.items.contains(where: { $0.sourceURL.path == url.path }) {
                showPasteAlert(title: S.pasteDuplicateTitle, message: S.pasteDuplicateMessage)
                return
            }
            userInitiatedAdd(localURLs: [url], remoteURLs: [], force: false, presetID: nil)
        case .remoteURL(let url):
            if vm.items.contains(where: { $0.pendingRemoteURL == url }) {
                showPasteAlert(title: S.pasteDuplicateTitle, message: S.pasteDuplicateMessage)
                return
            }
            userInitiatedAdd(localURLs: [], remoteURLs: [url], force: false, presetID: nil)
        }
    }

    private func shouldShowCompressionConfirmation() -> Bool {
        prefs.confirmBeforeEveryCompression
    }

    /// Drop, Open, Dock/Services, Clipboard — not watch folder.
    private func userInitiatedAdd(localURLs: [URL], remoteURLs: [URL], force: Bool, presetID: UUID?) {
        let hasWork = !localURLs.isEmpty || !remoteURLs.isEmpty
        guard hasWork else { return }
        guard shouldShowCompressionConfirmation() else {
            if !localURLs.isEmpty { vm.addAndCompress(localURLs, force: force, presetID: presetID) }
            if !remoteURLs.isEmpty {
                vm.queueRemoteDownload(
                    urls: remoteURLs,
                    force: force,
                    presetID: UUID(uuidString: prefs.activePresetID)
                )
            }
            return
        }
        pendingCompressionConfirmation = PendingCompressionConfirmation(
            localURLs: localURLs,
            remoteURLs: remoteURLs,
            force: force,
            presetID: presetID
        )
    }

    private func showPasteAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: String(localized: "OK", comment: "Alert dismiss button."))
        alert.runModal()
    }

    /// Dismisses SwiftUI presentations before `NSApp.reply(toApplicationShouldTerminate:)`.
    private func prepareForQuit() {
        showingHistory = false
        vm.pendingBatchSummary = nil
        batchSummaryFollowUp = nil
        pendingCompressionConfirmation = nil
        vm.undoErrorMessage = nil
        diagnostics.pendingCrashReport = nil
    }

    private var isUndoErrorAlertPresented: Binding<Bool> {
        Binding(
            get: { vm.undoErrorMessage != nil },
            set: { if !$0 { vm.undoErrorMessage = nil } }
        )
    }

    private func openBatchSummaryZeroGainDetail(for id: UUID) {
        if let item = vm.items.first(where: { $0.id == id }),
           case .zeroGain(let attempted) = item.status {
            batchSummaryFollowUp = .zeroGain(
                itemId: id,
                filename: item.filename,
                originalSize: item.originalSize,
                attemptedSize: attempted,
                isPDF: item.mediaType == .pdf,
                pdfOutputMode: item.zeroGainPDFOutputMode
            )
            return
        }
        if let row = vm.pendingBatchSummary?.fileRows.first(where: { $0.id == id }),
           case .zeroGain(_, let fn, _, let orig, let att, let isPDF, let raw) = row {
            batchSummaryFollowUp = .zeroGain(
                itemId: id,
                filename: fn,
                originalSize: orig,
                attemptedSize: att,
                isPDF: isPDF,
                pdfOutputMode: raw.flatMap { PDFOutputMode(rawValue: $0) }
            )
        }
    }

    private func openBatchSummaryFailedDetail(for id: UUID) {
        if let item = vm.items.first(where: { $0.id == id }),
           case .failed(let err) = item.status {
            batchSummaryFollowUp = .failed(itemId: id, filename: item.filename, error: err)
            return
        }
        if let row = vm.pendingBatchSummary?.fileRows.first(where: { $0.id == id }),
           case .failed(_, let fn, _, let desc) = row {
            let err = NSError(domain: "Dinky", code: 0, userInfo: [NSLocalizedDescriptionKey: desc])
            batchSummaryFollowUp = .failed(itemId: id, filename: fn, error: err)
        }
    }

    @ViewBuilder
    private func batchSummaryFollowUpSheetContent(_ follow: BatchSummaryFollowUpSheet) -> some View {
        switch follow {
        case .zeroGain(let itemId, let filename, let orig, let att, let isPDF, let mode):
            CompressionZeroGainDetailView(
                filename: filename,
                originalSize: orig,
                attemptedSize: att,
                isPDF: isPDF,
                pdfOutputMode: mode,
                onTryFlattenSmallest: (isPDF && (mode == .preserveStructure || mode == nil)) ? {
                    batchSummaryFollowUp = nil
                    if let item = vm.items.first(where: { $0.id == itemId }) {
                        vm.retryPDFFlattenSmallest(item)
                    }
                } : nil,
                onTryPreserveExperimental: (isPDF && (mode == .preserveStructure || mode == nil)) ? { exp in
                    batchSummaryFollowUp = nil
                    if let item = vm.items.first(where: { $0.id == itemId }) {
                        vm.retryPDFPreserveExperimental(item, mode: exp)
                    }
                } : nil
            )
        case .failed(_, let filename, let error):
            CompressionErrorDetailView(filename: filename, error: error)
        }
    }

    private var manualModeHintBanner: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "hand.tap")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(String(localized: "Manual mode: files stay queued until you tap Compress Now in the toolbar or bottom bar, right-click a row, or use File ▸ Compress Now (\(prefs.shortcut(for: .compressNow).displayString)).", comment: "Manual mode banner; argument is shortcut."))
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
        .accessibilityLabel(String(localized: "Manual mode is on. Files stay queued until you compress them with Compress Now in the toolbar or bottom bar, the row menu, or File menu Compress Now, \(prefs.shortcut(for: .compressNow).displayString).", comment: "VoiceOver: manual mode banner."))
    }

    /// Split from `body` so the Swift compiler can type-check the main window without timing out.
    private var mainWindowChrome: some View {
        ZStack(alignment: .leading) {
            VStack(spacing: 0) {
                if updater.shouldShow(dismissedVersion: prefs.dismissedUpdateVersion) {
                    VStack(spacing: 8) {
                        UpdateBanner(updater: updater, itemCount: vm.items.count)
                            .environmentObject(prefs)
                        if !reviewPromptBelowUpdateDismissed {
                            ReviewPromptBanner {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    reviewPromptBelowUpdateDismissed = true
                                }
                            }
                        }
                    }
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
            .onDrop(of: [.fileURL, .url], isTargeted: $isDropTargeted, perform: handleDrop)

            if sidebarVisible && !vm.isProcessing {
                GeometryReader { geo in
                    VStack {
                        SidebarView(
                            selectedFormat: Binding(
                                get: { vm.selectedFormat },
                                set: {
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
                    toggleSidebarVisible()
                } label: {
                    Label(String(localized: "Format & options", comment: "Toolbar: show or hide compression sidebar."), systemImage: "sidebar.left")
                        .symbolVariant(sidebarVisible ? .fill : .none)
                }
                .help(sidebarVisible ? String(localized: "Hide format, quality, and output options", comment: "Toolbar tooltip.") : String(localized: "Show format, quality, and output options", comment: "Toolbar tooltip."))
                .accessibilityLabel(sidebarVisible ? String(localized: "Hide format sidebar", comment: "VoiceOver.") : String(localized: "Show format sidebar", comment: "VoiceOver."))
            }
            if showCompressNowCTA {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        vm.compress()
                    } label: {
                        Label(String(localized: "Compress Now", comment: "Toolbar: run queued compression."), systemImage: "arrow.triangle.2.circlepath")
                    }
                    .help(String(localized: "Run compression on queued files (\(prefs.shortcut(for: .compressNow).displayString))", comment: "Toolbar: Compress Now help; argument is shortcut."))
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dinkyPrepareQuit)) { _ in prepareForQuit() }
    }

    var body: some View {
        mainWindowChrome
        .onReceive(NotificationCenter.default.publisher(for: .dinkyOpenPanel)) { _ in openPanel() }
        .onReceive(NotificationCenter.default.publisher(for: .dinkyOpenFiles)) { note in
            guard let urls = note.object as? [URL] else { return }
            userInitiatedAdd(localURLs: urls, remoteURLs: [], force: false, presetID: nil)
        }
        .onReceive(NotificationCenter.default.publisher(for: .dinkyPasteClipboard)) { _ in
            handlePasteFromUser()
        }
        .onReceive(NotificationCenter.default.publisher(for: .dinkyClearAll)) { _ in
            vm.clear()
            selectedIDs = []
        }
        .onReceive(NotificationCenter.default.publisher(for: .dinkyToggleSidebar)) { _ in
            toggleSidebarVisible()
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
        .onReceive(NotificationCenter.default.publisher(for: .dinkyShowLastBatchSummary)) { _ in
            vm.showLastBatchSummary()
        }
        .sheet(isPresented: $showingHistory) {
            HistorySheet(
                onOpenSessionSummary: { record in
                    guard let data = record.batchSummaryData,
                          let summary = try? JSONDecoder().decode(CompressionBatchSummary.self, from: data)
                    else { return }
                    showingHistory = false
                    vm.presentHistoricalBatchSummary(summary)
                }
            )
            .environmentObject(prefs)
        }
        .sheet(item: $vm.pendingBatchSummary) { summary in
            BatchCompletionSummarySheet(
                summary: summary,
                supportsUndo: vm.pendingBatchSummarySupportsUndo,
                openPreferences: revealPreferences,
                onUndoAll: { vm.undoAllCompressibleDone() },
                onUndoItem: { id in
                    if let item = vm.items.first(where: { $0.id == id }) {
                        vm.undoCompression(item)
                    }
                },
                onQueueCompress: { id in
                    if let item = vm.items.first(where: { $0.id == id }) {
                        vm.forceCompress(item)
                    }
                },
                onOpenZeroGainDetail: { openBatchSummaryZeroGainDetail(for: $0) },
                onOpenFailedDetail: { openBatchSummaryFailedDetail(for: $0) },
                onPDFFlattenSmallest: { id in
                    if let item = vm.items.first(where: { $0.id == id }) {
                        vm.retryPDFFlattenSmallest(item)
                    }
                },
                onPDFPreserveExperimental: { id, mode in
                    if let item = vm.items.first(where: { $0.id == id }) {
                        vm.retryPDFPreserveExperimental(item, mode: mode)
                    }
                }
            )
        }
        .sheet(item: $batchSummaryFollowUp) { follow in
            batchSummaryFollowUpSheetContent(follow)
        }
        .sheet(item: $pendingCompressionConfirmation) { pending in
            CompressionConfirmationSheet(
                selectedFormat: Binding(
                    get: { vm.selectedFormat },
                    set: { vm.selectedFormat = $0 }
                ),
                localURLs: pending.localURLs,
                remoteURLs: pending.remoteURLs,
                openPreferences: revealPreferences,
                onCancel: { pendingCompressionConfirmation = nil },
                onContinue: {
                    let batchPresetID = UUID(uuidString: prefs.activePresetID)
                    if !pending.localURLs.isEmpty {
                        vm.addAndCompress(pending.localURLs, force: pending.force, presetID: batchPresetID)
                    }
                    if !pending.remoteURLs.isEmpty {
                        vm.queueRemoteDownload(urls: pending.remoteURLs, force: pending.force, presetID: batchPresetID)
                    }
                    pendingCompressionConfirmation = nil
                }
            )
            .environmentObject(prefs)
        }
        .onChange(of: vm.pendingBatchSummary?.id) { _, newId in
            if newId == nil {
                vm.onBatchSummaryDismissed()
            }
        }
        .alert(
            String(localized: "Couldn’t undo", comment: "Undo error alert title."),
            isPresented: isUndoErrorAlertPresented
        ) {
            Button(String(localized: "OK", comment: "Alert dismiss.")) {
                vm.undoErrorMessage = nil
            }
        } message: {
            Text(vm.undoErrorMessage ?? "")
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
                showBottomDivider: item.id != vm.items.last?.id,
                onForceCompress: { vm.forceCompress(item) },
                onCancelDownload: { vm.remove(item) },
                onPDFFlattenSmallestRetry: { vm.retryPDFFlattenSmallest(item) },
                onPDFPreserveExperimentalRetry: { vm.retryPDFPreserveExperimental(item, mode: $0) }
            )
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
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
                            Button { vm.compressItems(targets, format: .heic) } label: {
                                Label(String(localized: "Compress as HEIC", comment: "Context menu."), systemImage: "photo")
                            }
                            Divider()
                        }
                        if item.mediaType == .pdf, vm.effectivePDFOutputMode(for: item) == .flattenPages {
                            Button { vm.queuePDFCompressAtQuality(targets, quality: .low) } label: {
                                Label(String(localized: "Compress PDF at Low", comment: "Context menu PDF quality."), systemImage: "doc")
                            }
                            Button { vm.queuePDFCompressAtQuality(targets, quality: .medium) } label: {
                                Label(String(localized: "Compress PDF at Medium", comment: "Context menu PDF quality."), systemImage: "doc")
                            }
                            Button { vm.queuePDFCompressAtQuality(targets, quality: .high) } label: {
                                Label(String(localized: "Compress PDF at High", comment: "Context menu PDF quality."), systemImage: "doc")
                            }
                            Divider()
                        }
                        if item.mediaType == .video {
                            Menu {
                                Button(VideoQuality.medium.displayName) { vm.queueVideoCompress(targets, quality: .medium, codec: .h264) }
                                Button(VideoQuality.high.displayName)   { vm.queueVideoCompress(targets, quality: .high,   codec: .h264) }
                            } label: {
                                Label(String(localized: "Compress H.264", comment: "Video codec menu."), systemImage: "film")
                            }
                            Menu {
                                Button(VideoQuality.medium.displayName) { vm.queueVideoCompress(targets, quality: .medium, codec: .hevc) }
                                Button(VideoQuality.high.displayName)   { vm.queueVideoCompress(targets, quality: .high,   codec: .hevc) }
                            } label: {
                                Label(String(localized: "Compress H.265 (HEVC)", comment: "Video codec menu."), systemImage: "film")
                            }
                            Divider()
                        }
                    } else {
                        let undoTargets: [CompressionItem] = {
                            if selectedIDs.contains(item.id) {
                                return vm.items.filter { selectedIDs.contains($0.id) && $0.undoSnapshot != nil }
                            }
                            return item.undoSnapshot != nil ? [item] : []
                        }()
                        if !undoTargets.isEmpty {
                            Button {
                                for t in undoTargets.reversed() {
                                    vm.undoCompression(t)
                                }
                            } label: {
                                if undoTargets.count == 1 {
                                    Label(String(localized: "Undo compression", comment: "Context menu: revert one compression."), systemImage: "arrow.uturn.backward")
                                } else {
                                    Label(String.localizedStringWithFormat(
                                        String(localized: "Undo %lld compressions", comment: "Context menu: revert multiple compressions."),
                                        Int64(undoTargets.count)
                                    ), systemImage: "arrow.uturn.backward")
                                }
                            }
                            Divider()
                        }
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
                            Button { vm.recompress(item, as: .heic) } label: {
                                Label(String(localized: "Re-compress as HEIC", comment: "Context menu."), systemImage: "photo")
                            }
                            Divider()
                        }
                        if item.mediaType == .pdf, vm.effectivePDFOutputMode(for: item) == .flattenPages {
                            Button { vm.recompressPDF(item, quality: .low) } label: {
                                Label(String(localized: "Re-compress PDF at Low", comment: "Context menu."), systemImage: "doc")
                            }
                            Button { vm.recompressPDF(item, quality: .medium) } label: {
                                Label(String(localized: "Re-compress PDF at Medium", comment: "Context menu."), systemImage: "doc")
                            }
                            Button { vm.recompressPDF(item, quality: .high) } label: {
                                Label(String(localized: "Re-compress PDF at High", comment: "Context menu."), systemImage: "doc")
                            }
                            Divider()
                        }
                        if item.mediaType == .video {
                            Menu {
                                Button(VideoQuality.medium.displayName) { vm.recompressVideo(item, quality: .medium, codec: .h264) }
                                Button(VideoQuality.high.displayName)   { vm.recompressVideo(item, quality: .high,   codec: .h264) }
                            } label: {
                                Label(String(localized: "Re-compress H.264", comment: "Video codec menu."), systemImage: "film")
                            }
                            Menu {
                                Button(VideoQuality.medium.displayName) { vm.recompressVideo(item, quality: .medium, codec: .hevc) }
                                Button(VideoQuality.high.displayName)   { vm.recompressVideo(item, quality: .high,   codec: .hevc) }
                            } label: {
                                Label(String(localized: "Re-compress H.265 (HEVC)", comment: "Video codec menu."), systemImage: "film")
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
        HStack(alignment: .center, spacing: 12) {
            if showCompressNowCTA {
                Button {
                    vm.compress()
                } label: {
                    Text(String(localized: "Compress Now (\(prefs.shortcut(for: .compressNow).displayString))", comment: "Bottom bar: run queue; argument is shortcut."))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .help(String(localized: "Run compression on queued files", comment: "Bottom bar button help."))
            }

            if showContinueCTA {
                Button {
                    vm.compress()
                } label: {
                    Text(String(localized: "Continue", comment: "Bottom bar: resume queue after Stop."))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .help(String(localized: "Resume compressing files that are still waiting.", comment: "Bottom bar: Continue help."))
            }

            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(vm.isEmpty ? .center : .leading)
                .frame(maxWidth: .infinity, alignment: vm.isEmpty ? .center : .leading)
                .animation(.easeInOut, value: vm.phase)

            if vm.isProcessing {
                Button {
                    vm.stopCompression()
                } label: {
                    Text(String(localized: "Stop", comment: "Bottom bar: cancel in-flight compression."))
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                .help(String(localized: "Stop after current work winds down; remaining files stay queued. Use Continue to resume.", comment: "Bottom bar: Stop help."))
            }

            if !vm.isEmpty {
                Button(String(localized: "Clear All", comment: "Bottom bar: clear list.")) { vm.clear() }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
            if collected.isEmpty, remoteURLs.isEmpty { return }
            userInitiatedAdd(localURLs: collected, remoteURLs: remoteURLs, force: force, presetID: nil)
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
        panel.allowedContentTypes     = [.jpeg, .png, .webP, .heic, .heif, .image, .pdf, .mpeg4Movie, .quickTimeMovie, .movie]
        if panel.runModal() == .OK {
            userInitiatedAdd(localURLs: panel.urls, remoteURLs: [], force: false, presetID: nil)
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

        // If the user already kicked off an install (e.g. hit Install Update twice),
        // don't stack another Task on top — downloadAndInstall guards against this too,
        // but skipping the alert avoids the confusing "keep popping up" appearance.
        guard case .idle = updater.installState else { return }
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
