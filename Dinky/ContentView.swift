import SwiftUI
import UniformTypeIdentifiers
import UserNotifications
import Darwin
import AppKit

enum PasteClipboardResult {
    case added
    case emptyClipboard
    case duplicateInQueue
}

@MainActor
final class ContentViewModel: ObservableObject {
    @Published var items: [ImageItem] = []
    @Published var isProcessing = false
    @Published var phase: DropZonePhase = .idle
    private var compressionStartTime: Date = .now

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
        cleanupPasteTemps(for: [item])
        items.removeAll { $0.id == item.id }
        if items.isEmpty { phase = .idle }
    }

    func pasteClipboard() -> PasteClipboardResult {
        guard let url = ClipboardImporter.importFromClipboard() else { return .emptyClipboard }
        if items.contains(where: { $0.sourceURL.path == url.path }) { return .duplicateInQueue }
        addAndCompress([url])
        return .added
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
        isProcessing = true
        phase = .processing
        compressionStartTime = .now

        let pending = items.filter { if case .pending = $0.status { return true }; return false }
        let batchPreset = batchSharedPreset(from: pending)

        Task {
            await withTaskGroup(of: Void.self) { group in
                let mediaSem = AsyncSemaphore(limit: prefs.concurrentCompressionLimit)
                let videoSem = AsyncSemaphore(limit: Self.concurrentVideoExportLimit)
                for item in pending {
                    switch item.mediaType {
                    case .video:
                        await videoSem.wait()
                    case .image, .pdf:
                        await mediaSem.wait()
                    }
                    group.addTask { [weak self] in
                        defer {
                            switch item.mediaType {
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
                self.phase = .done
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
            }
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
        let outputURL: URL = {
            if let pr = preset { return pr.outputURL(for: item.sourceURL, format: format, globalPrefs: prefs) }
            return prefs.outputURL(for: item.sourceURL, format: format)
        }()
        let replaceOrigin = (preset.map { FilenameHandling(rawValue: $0.filenameHandlingRaw) } ?? prefs.filenameHandling) == .replaceOrigin
        do {
            let result = try await CompressionService.shared.compress(
                source: item.sourceURL,
                format: format,
                goals: goals,
                stripMetadata: strip,
                outputURL: outputURL,
                moveToTrash: prefs.moveOriginalsToTrash,
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
                    if replaceOrigin {
                        try? FileManager.default.trashItem(at: item.sourceURL, resultingItemURL: nil)
                    }
                    if self.prefs.preserveTimestamps {
                        self.copyTimestamp(from: item.sourceURL, to: result.outputURL)
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
        await MainActor.run { item.status = .processing }
        let intendedOutput: URL = {
            if let pr = preset { return pr.outputURL(for: item.sourceURL, mediaType: .pdf, globalPrefs: prefs) }
            return prefs.outputURL(for: item.sourceURL, mediaType: .pdf)
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
                    try? FileManager.default.trashItem(at: item.sourceURL, resultingItemURL: nil)
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
        await MainActor.run {
            item.status = .processing
            item.videoExportProgress = 0
        }
        defer { item.videoExportProgress = nil }
        let intendedOutput: URL = {
            if let pr = preset { return pr.outputURL(for: item.sourceURL, mediaType: .video, globalPrefs: prefs) }
            return prefs.outputURL(for: item.sourceURL, mediaType: .video)
        }()
        let videoFallback = preset.map { VideoQuality(rawValue: $0.videoQualityRaw) ?? .medium } ?? prefs.videoQuality
        let sourceURL = item.sourceURL
        let asset = VideoCompressor.makeURLAsset(url: sourceURL)
        let smartQ = preset?.smartQuality ?? prefs.smartQuality
        let removeAudio = preset?.videoRemoveAudio ?? prefs.videoRemoveAudio
        let codec: VideoCodecFamily
        let videoQuality: VideoQuality
        if let o = videoOverride {
            videoQuality = o.quality
            codec = o.codec
        } else {
            codec = preset.map { VideoCodecFamily(rawValue: $0.videoCodecFamilyRaw) ?? .h264 } ?? prefs.videoCodecFamily
            if smartQ {
                videoQuality = await VideoSmartQuality.inferQuality(asset: asset, fallback: videoFallback)
            } else {
                videoQuality = videoFallback
            }
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
                outputURL: workURL,
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
                    try? FileManager.default.trashItem(at: item.sourceURL, resultingItemURL: nil)
                }
            }

            let outSize = (try? producedURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map { Int64($0) }
                ?? result.outputSize
            let savings = result.originalSize > 0
                ? Double(result.originalSize - outSize) / Double(result.originalSize) : 0
            await MainActor.run {
                item.videoDuration = result.videoDuration
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

struct PNGInputError: LocalizedError {
    var errorDescription: String? {
        "PNG lossless only works on PNG files. Try WebP or AVIF for this one."
    }
}

// MARK: - Root view

struct ContentView: View {
    @EnvironmentObject var prefs: DinkyPreferences
    @EnvironmentObject var updater: UpdateChecker
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
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private var manualModeHintBanner: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "hand.tap")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Manual mode: files stay queued until you right-click a row or choose Compress Now (⌘↩) from the File menu.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Got it") {
                manualModeHintDismissed = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            Button("Settings…") {
                revealPreferences(.general)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .adaptiveGlass(in: RoundedRectangle(cornerRadius: 0, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Manual mode is on. Files stay queued until you compress them from the row menu or File menu.")
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
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)

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
                    Label("Toggle Sidebar", systemImage: "sidebar.left")
                        .symbolVariant(sidebarVisible ? .fill : .none)
                }
                .help(sidebarVisible ? "Hide the format sidebar" : "Show the format sidebar")
                .accessibilityLabel(sidebarVisible ? "Hide format sidebar" : "Show format sidebar")
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
            prefs.reconcileSidebarSectionsForSimpleModeIfNeeded()
            updateFolderWatcher()
        }
        .task {
            await updater.check()
        }
        .onChange(of: prefs.folderWatchEnabled) { _, _ in updateFolderWatcher() }
        .onChange(of: prefs.watchedFolderPath) { _, _ in updateFolderWatcher() }
        .onChange(of: prefs.watchedFolderBookmark) { _, _ in updateFolderWatcher() }
        .onChange(of: prefs.savedPresetsData) { _, _ in updateFolderWatcher() }
    }

    // MARK: - Results list

    private var resultsList: some View {
        List(vm.items, id: \.id, selection: $selectedIDs) { item in
            ResultsRowView(item: item, selectedFormat: vm.selectedFormat, onForceCompress: { vm.forceCompress(item) })
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.visible)
                .listRowSeparatorTint(.primary.opacity(0.08))
                .onTapGesture(count: 2) {
                    let url = item.outputURL ?? item.sourceURL
                    NSWorkspace.shared.open(url)
                }
                .onDrag {
                    let url = item.outputURL ?? item.sourceURL
                    return NSItemProvider(contentsOf: url) ?? NSItemProvider()
                }
                .contextMenu {
                    if case .processing = item.status {
                        EmptyView()
                    } else if case .pending = item.status {
                        let targets = selectedIDs.contains(item.id)
                            ? vm.items.filter { selectedIDs.contains($0.id) }
                            : [item]
                        if item.mediaType == .image {
                            Button { vm.compressItems(targets, format: .webp) } label: {
                                Label("Compress as WebP", systemImage: "photo")
                            }
                            Button { vm.compressItems(targets, format: .avif) } label: {
                                Label("Compress as AVIF", systemImage: "photo")
                            }
                            Button { vm.compressItems(targets, format: .png) } label: {
                                Label("Compress as PNG", systemImage: "photo")
                            }
                            Divider()
                        }
                        if item.mediaType == .pdf, vm.effectivePDFOutputMode(for: item) == .flattenPages {
                            Button { vm.queuePDFCompressAtQuality(targets, quality: .low) } label: {
                                Label("Compress at Low", systemImage: "doc")
                            }
                            Button { vm.queuePDFCompressAtQuality(targets, quality: .medium) } label: {
                                Label("Compress at Medium", systemImage: "doc")
                            }
                            Button { vm.queuePDFCompressAtQuality(targets, quality: .high) } label: {
                                Label("Compress at High", systemImage: "doc")
                            }
                            Divider()
                        }
                        if item.mediaType == .video {
                            Menu {
                                Button("Low") { vm.queueVideoCompress(targets, quality: .low, codec: .h264) }
                                Button("Medium") { vm.queueVideoCompress(targets, quality: .medium, codec: .h264) }
                                Button("High") { vm.queueVideoCompress(targets, quality: .high, codec: .h264) }
                            } label: {
                                Label("H.264", systemImage: "film")
                            }
                            Menu {
                                Button("Low") { vm.queueVideoCompress(targets, quality: .low, codec: .hevc) }
                                Button("Medium") { vm.queueVideoCompress(targets, quality: .medium, codec: .hevc) }
                                Button("High") { vm.queueVideoCompress(targets, quality: .high, codec: .hevc) }
                            } label: {
                                Label("H.265 (HEVC)", systemImage: "film")
                            }
                            Divider()
                        }
                    } else {
                        if case .skipped = item.status {
                            Button { vm.forceCompress(item) } label: {
                                Label("Compress Anyway", systemImage: "arrow.clockwise")
                            }
                            Divider()
                        }
                        if item.mediaType == .image {
                            Button { vm.recompress(item, as: .webp) } label: {
                                Label("Re-compress as WebP", systemImage: "photo")
                            }
                            Button { vm.recompress(item, as: .avif) } label: {
                                Label("Re-compress as AVIF", systemImage: "photo")
                            }
                            Button { vm.recompress(item, as: .png) } label: {
                                Label("Re-compress as PNG", systemImage: "photo")
                            }
                            Divider()
                        }
                        if item.mediaType == .pdf, vm.effectivePDFOutputMode(for: item) == .flattenPages {
                            Button { vm.recompressPDF(item, quality: .low) } label: {
                                Label("Re-compress at Low", systemImage: "doc")
                            }
                            Button { vm.recompressPDF(item, quality: .medium) } label: {
                                Label("Re-compress at Medium", systemImage: "doc")
                            }
                            Button { vm.recompressPDF(item, quality: .high) } label: {
                                Label("Re-compress at High", systemImage: "doc")
                            }
                            Divider()
                        }
                        if item.mediaType == .video {
                            Menu {
                                Button("Low") { vm.recompressVideo(item, quality: .low, codec: .h264) }
                                Button("Medium") { vm.recompressVideo(item, quality: .medium, codec: .h264) }
                                Button("High") { vm.recompressVideo(item, quality: .high, codec: .h264) }
                            } label: {
                                Label("H.264", systemImage: "film")
                            }
                            Menu {
                                Button("Low") { vm.recompressVideo(item, quality: .low, codec: .hevc) }
                                Button("Medium") { vm.recompressVideo(item, quality: .medium, codec: .hevc) }
                                Button("High") { vm.recompressVideo(item, quality: .high, codec: .hevc) }
                            } label: {
                                Label("H.265 (HEVC)", systemImage: "film")
                            }
                            Divider()
                        }
                    }
                    Button {
                        vm.remove(item)
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                    Divider()
                    Button(role: .destructive) {
                        vm.clear()
                    } label: {
                        Label("Clear All", systemImage: "trash.fill")
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
                    Button("Clear All") { vm.clear() }
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
        let force = NSEvent.modifierFlags.contains(.option)
        let group = DispatchGroup()
        let lock  = NSLock()

        for provider in providers {
            guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { continue }
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
        }

        group.notify(queue: .main) {
            guard !collected.isEmpty else { return }
            vm.addAndCompress(collected, force: force)
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
        alert.informativeText = "Version \(version) is out. You're on \(currentAppVersion()). Want it?"
        alert.addButton(withTitle: "Install Update")
        alert.addButton(withTitle: "What's new")
        alert.addButton(withTitle: "Maybe later")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            Task { await updater.downloadAndInstall() }
        } else if response == .alertSecondButtonReturn, let url = updater.releaseURL {
            NSWorkspace.shared.open(url)
        }

    case .upToDate:
        alert.messageText = "All caught up."
        alert.informativeText = "You're on Dinky \(currentAppVersion()) — the latest and dinkyest."
        alert.addButton(withTitle: "Nice")
        alert.runModal()

    case .failed:
        alert.alertStyle = .warning
        alert.messageText = "Couldn't phone home."
        alert.informativeText = "Dinky couldn't reach GitHub. Probably the internet. Try again in a sec?"
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

private func currentAppVersion() -> String {
    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
}
