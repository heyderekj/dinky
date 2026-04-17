import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import UserNotifications

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

    var isEmpty: Bool { items.isEmpty }

    func addAndCompress(_ urls: [URL]) {
        let new = urls.map { ImageItem(sourceURL: $0) }
        items.append(contentsOf: new)
        if !prefs.manualMode { compress() }
    }

    func compressItems(_ targets: [ImageItem], format: CompressionFormat) {
        for item in targets {
            item.formatOverride = format
        }
        compress()
    }

    func recompress(_ item: ImageItem, as format: CompressionFormat) {
        item.formatOverride = format
        item.status = .pending
        compress()
    }

    func clear() {
        cleanupPasteTemps(for: items)
        items = []
        phase = .idle
    }

    func remove(_ item: ImageItem) {
        cleanupPasteTemps(for: [item])
        items.removeAll { $0.id == item.id }
        if items.isEmpty { phase = .idle }
    }

    func pasteClipboard() {
        guard let url = ClipboardImporter.importFromClipboard() else { return }
        addAndCompress([url])
    }

    private func cleanupPasteTemps(for targets: [ImageItem]) {
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
        let goals   = CompressionGoals(
            maxWidth:      prefs.maxWidthEnabled     ? prefs.maxWidth      : nil,
            maxFileSizeKB: prefs.maxFileSizeEnabled  ? prefs.maxFileSizeKB : nil
        )

        Task {
            await withTaskGroup(of: Void.self) { group in
                let sem = AsyncSemaphore(limit: prefs.concurrentTasks)
                for item in pending {
                    await sem.wait()
                    group.addTask { [weak self] in
                        defer { Task { await sem.signal() } }
                        await self?.compressItem(item, goals: goals)
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
                        return (item.formatOverride ?? self.selectedFormat).displayName
                    })).sorted()
                    let record = SessionRecord(id: UUID(), timestamp: .now,
                                              fileCount: doneCount,
                                              totalBytesSaved: batchSaved,
                                              formats: formats)
                    var history = self.prefs.sessionHistory
                    history.insert(record, at: 0)
                    self.prefs.sessionHistory = Array(history.prefix(50))
                }

                if self.prefs.playSoundEffects { self.playCompletionSound() }

                let elapsed = Date.now.timeIntervalSince(self.compressionStartTime)
                let doneItems = self.items.compactMap { item -> URL? in
                    if case .done(let url, _, _) = item.status { return url } else { return nil }
                }

                if self.prefs.openFolderWhenDone, let first = doneItems.first {
                    NSWorkspace.shared.open(first.deletingLastPathComponent())
                }

                if self.prefs.notifyWhenDone {
                    self.sendNotification(count: doneItems.count, seconds: elapsed)
                }
            }
        }
    }

    private func compressItem(_ item: ImageItem, goals: CompressionGoals) async {
        var format = item.formatOverride ?? selectedFormat
        if prefs.autoFormat && item.formatOverride == nil {
            let ct = ContentClassifier.classify(item.sourceURL)
            await MainActor.run { item.detectedContentType = ct }
            format = ct == .photo ? .avif : .webp
        }

        // PNG lossless only accepts PNG inputs — suggest alternatives for other formats
        if format == .png && item.sourceURL.pathExtension.lowercased() != "png" {
            await MainActor.run { item.status = .failed(PNGInputError()) }
            return
        }

        await MainActor.run { item.status = .processing }
        let outputURL = prefs.outputURL(for: item.sourceURL, format: format)
        do {
            let result = try await CompressionService.shared.compress(
                source: item.sourceURL,
                format: format,
                goals: goals,
                stripMetadata: prefs.stripMetadata,
                outputURL: outputURL,
                moveToTrash: prefs.moveOriginalsToTrash,
                smartQuality: prefs.smartQuality
            )
            let savings = result.originalSize > 0
                ? Double(result.originalSize - result.outputSize) / Double(result.originalSize) : 0
            await MainActor.run {
                item.detectedContentType = result.detectedContentType
                if result.outputSize >= result.originalSize {
                    item.status = .zeroGain(original: item.sourceURL)
                    try? FileManager.default.removeItem(at: result.outputURL)
                } else if self.prefs.skipAlreadyOptimized && savings < 0.02 {
                    item.status = .skipped
                    try? FileManager.default.removeItem(at: result.outputURL)
                } else {
                    item.status = .done(outputURL: result.outputURL,
                                        originalSize: result.originalSize,
                                        outputSize: result.outputSize)
                    if self.prefs.filenameHandling == .replaceOrigin {
                        try? FileManager.default.trashItem(at: item.sourceURL, resultingItemURL: nil)
                    }
                    if self.prefs.preserveTimestamps {
                        copyTimestamp(from: item.sourceURL, to: result.outputURL)
                    }
                }
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
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let body: String
            switch (count, seconds) {
            case (0, _):          body = "Done. Nothing got smaller though."
            case (1, ..<3):       body = "1 image, considerably dinky-er."
            case (1, _):          body = "1 image. Took a sec, worth it."
            case (2...5, ..<5):   body = "\(count) images. Done before you blinked."
            case (2...5, _):      body = "\(count) images, all shrunk down."
            case (6...20, ..<10): body = "\(count) images compressed. The internet will thank you."
            case (6...20, _):     body = "\(count) images. Your pages just got faster."
            default:              body = "\(count) images. That's a lot of rectangles — all smaller now."
            }
            let content = UNMutableNotificationContent()
            content.title = "Dinky"
            content.body = body
            content.sound = .default
            let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(req)
        }
    }

    private func playCompletionSound() {
        let sr = 44100.0, dur = 0.35
        let fc = AVAudioFrameCount(sr * dur)
        let engine = AVAudioEngine(); let player = AVAudioPlayerNode()
        engine.attach(player)
        let fmt = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1)!
        guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: fc) else { return }
        buf.frameLength = fc
        let d = buf.floatChannelData![0]
        for i in 0..<Int(fc) {
            let t = Double(i) / sr
            d[i] = Float(max(0, 1 - t/dur)) * 0.22 * Float(sin(2 * .pi * (600 - 300*(t/dur)) * t))
        }
        engine.connect(player, to: engine.mainMixerNode, format: fmt)
        try? engine.start(); player.scheduleBuffer(buf); player.play()
        DispatchQueue.main.asyncAfter(deadline: .now() + dur + 0.1) { engine.stop() }
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
    @ObservedObject var vm: ContentViewModel
    @StateObject private var folderWatcher = FolderWatcher()
    @State private var sidebarVisible = false
    @State private var isDropTargeted  = false
    @State private var idleLoop        = 0
    @State private var selectedIDs: Set<UUID> = []
    @State private var showingHistory  = false

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

    var body: some View {
        ZStack(alignment: .leading) {
            // ── Main content (drop target covers the full surface) ──
            VStack(spacing: 0) {
                if updater.shouldShow(dismissedVersion: prefs.dismissedUpdateVersion) {
                    UpdateBanner(updater: updater)
                        .environmentObject(prefs)
                }
                if vm.isEmpty {
                    DropZoneView(phase: dropPhase, onOpenPanel: openPanel, onPaste: { vm.pasteClipboard() }, onLoop: { idleLoop += 1 })
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
                        SidebarView(selectedFormat: Binding(
                            get:  { vm.selectedFormat },
                            set:  { vm.selectedFormat = $0 }
                        ))
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
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dinkyOpenPanel)) { _ in openPanel() }
        .onReceive(NotificationCenter.default.publisher(for: .dinkyOpenFiles)) { note in
            guard let urls = note.object as? [URL] else { return }
            vm.addAndCompress(urls)
        }
        .onReceive(NotificationCenter.default.publisher(for: .dinkyPasteClipboard)) { _ in
            vm.pasteClipboard()
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
        .task {
            // Defer the first check so the window settles before any network I/O.
            if prefs.checkForUpdatesOnLaunch {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                await updater.check(skipThrottle: true)
            }
        }
        .onAppear { updateFolderWatcher() }
        .onChange(of: prefs.folderWatchEnabled) { _, _ in updateFolderWatcher() }
        .onChange(of: prefs.watchedFolderPath)  { _, _ in updateFolderWatcher() }
    }

    // MARK: - Results list

    private var resultsList: some View {
        List(vm.items, id: \.id, selection: $selectedIDs) { item in
            ResultsRowView(item: item, selectedFormat: vm.selectedFormat)
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
                    } else {
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
                if prefs.lifetimeSavedBytes > 0 {
                    Text(lifetimeSavingsText)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
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

    private var lifetimeSavingsText: String {
        let mb = Double(prefs.lifetimeSavedBytes) / 1_048_576
        if mb >= 1024 { return String(format: "%.1f GB saved", mb / 1024) }
        return String(format: "%.0f MB saved", mb)
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
            vm.addAndCompress(collected)
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
        return urls.filter { ["jpg","jpeg","png","webp","avif","tiff","bmp"].contains($0.pathExtension.lowercased()) }
    }

    // MARK: - Folder watcher

    private func updateFolderWatcher() {
        guard prefs.folderWatchEnabled, !prefs.watchedFolderPath.isEmpty else {
            folderWatcher.stop(); return
        }
        folderWatcher.onNewFiles = { urls in vm.addAndCompress(urls) }
        folderWatcher.start(at: prefs.watchedFolderPath)
    }

    // MARK: - Open panel

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories    = true
        panel.allowedContentTypes     = [.jpeg, .png, .webP, .image]
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
