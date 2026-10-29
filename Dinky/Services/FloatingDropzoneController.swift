import AppKit
import SwiftUI
import Combine
import DinkyCoreShared

/// The floating dropzone: a small glass panel that tucks into a screen corner while files are
/// dragged anywhere, compresses what's dropped on it without opening the main window, and shows
/// the results there so they can be dragged straight back out.
@MainActor
final class FloatingDropzoneController: ObservableObject {
    static let shared = FloatingDropzoneController()

    enum Stage: Equatable {
        case hidden
        /// Files are being dragged somewhere on screen.
        case dragging
        /// Files were dropped here and are compressing.
        case working
        /// Everything dropped here finished; results are showing.
        case done
    }

    @Published private(set) var stage: Stage = .hidden
    @Published private(set) var dragged: FileDragWatcher.DraggedFiles?
    /// 0 when the pointer is far away, 1 when it's on the dropzone. Drives the swell.
    @Published private(set) var proximity: CGFloat = 0
    /// Near enough to show the full target and the preset tiles.
    @Published private(set) var isExpanded = false
    /// Rows this dropzone queued, newest drop only. Held here so auto-clear in the main
    /// list doesn't take them away from the results.
    @Published private(set) var results: [CompressionItem] = []
    /// Size of each result's original when it was dropped (the source can be replaced in place).
    @Published private(set) var originalSizes: [UUID: Int64] = [:]
    @Published private(set) var corner: ScreenCorner = .bottomRight
    /// One `ID` per drop, so the view can replay its drop animation.
    @Published private(set) var dropID = UUID()

    /// Hovering pauses the tuck-away after results show.
    var isHovering = false {
        didSet {
            guard isHovering != oldValue, stage == .done else { return }
            if isHovering { cancelPendingHide() } else { scheduleHide(after: Self.resultsLinger) }
        }
    }

    private let watcher = FileDragWatcher()
    private var panel: FloatingDropzonePanel?
    private var statusWatch: AnyCancellable?
    private var hideTask: Task<Void, Never>?
    private var resizeTask: Task<Void, Never>?

    /// Room for the collapsed pill plus the swell and shadow around it.
    static let collapsedSize = CGSize(width: 280, height: 150)
    /// Room for the full target with preset tiles, progress or results.
    static let expandedSize = CGSize(width: 320, height: 430)
    /// Gap from the screen's visible edge, enough to keep clear of hot corners and Quick Note.
    static let edgeInset: CGFloat = 14
    private static let resultsLinger: TimeInterval = 4
    private static let tuckDuration: TimeInterval = 0.4

    private var prefs: DinkyPreferences { DinkyRootModel.shared.prefs }

    private init() {
        watcher.onEvent = { [weak self] event in self?.handle(event) }
    }

    // MARK: - Settings

    /// Starts or stops watching drags to match Settings.
    func syncFromDefaults() {
        corner = prefs.floatingDropzoneCorner
        if prefs.floatingDropzoneEnabled {
            watcher.start()
        } else {
            watcher.stop()
            hide(animated: false)
        }
        if stage != .hidden { positionPanel() }
    }

    // MARK: - What the view shows

    private var activePreset: CompressionPreset? {
        prefs.savedPresets.first { $0.id.uuidString == prefs.activePresetID }
    }

    /// The big target's caption: the preset it will use.
    var mainTargetSubtitle: String {
        activePreset?.name ?? String(localized: "Your settings", comment: "Floating dropzone: main target uses the sidebar settings, not a preset.")
    }

    /// Saved presets (other than the active one) that cover what's being dragged. Up to three,
    /// so the track's segments stay readable.
    var tilePresets: [CompressionPreset] {
        let media = dragged?.mediaTypes ?? []
        let activeID = activePreset?.id
        return Array(prefs.savedPresets.filter { preset in
            preset.id != activeID && (media.isEmpty || media.contains { preset.applies(to: $0) })
        }.prefix(3))
    }

    // MARK: - Drag events

    private func handle(_ event: FileDragWatcher.Event) {
        switch event {
        case .began(let files):
            cancelPendingHide()
            dragged = files
            proximity = 0
            setExpanded(false)
            stage = .dragging
            showPanel()
        case .moved(let point):
            guard stage == .dragging else { return }
            updateProximity(to: point)
        case .ended:
            // The drop (if it was on us) arrives around the same mouse-up; give it a moment.
            guard stage == .dragging else { return }
            scheduleHide(after: 0.25)
        }
    }

    private func updateProximity(to point: NSPoint) {
        guard let frame = panel?.frame else { return }
        let target = pillCenter(in: frame)
        let distance = hypot(point.x - target.x, point.y - target.y)
        // Starts swelling ~420pt out, full size within ~90pt.
        let p = min(1, max(0, 1 - (distance - 90) / 330))
        proximity = p
        // Hysteresis so the panel doesn't flicker open and shut at the boundary.
        if !isExpanded, p > 0.6 { setExpanded(true) }
        else if isExpanded, p < 0.4 { setExpanded(false) }
    }

    /// Roughly where the pill sits: the corner of the panel nearest the screen corner.
    private func pillCenter(in frame: NSRect) -> NSPoint {
        let x = corner.isLeft ? frame.minX + 110 : frame.maxX - 110
        let y = corner.isTop ? frame.maxY - 40 : frame.minY + 40
        return NSPoint(x: x, y: y)
    }

    /// Called by the view while a drag hovers a target, so it opens even if the pointer
    /// came in faster than the move events.
    func dragEnteredTarget() {
        guard stage == .dragging else { return }
        proximity = 1
        setExpanded(true)
    }

    // MARK: - Drop

    /// `presetID == nil` uses the active preset, the same as dropping on the main window.
    func accept(_ providers: [NSItemProvider], presetID: UUID?) -> Bool {
        let force = NSEvent.modifierFlags.contains(.option)
        cancelPendingHide()
        stage = .working
        setExpanded(true)
        dropID = UUID()
        DroppedItemsReader.read(providers) { [weak self] local, remote in
            guard let self else { return }
            let vm = DinkyRootModel.shared.contentVM
            var ids: [UUID] = []
            if !local.isEmpty {
                if let presetID {
                    ids += vm.addAndCompress(local, force: force, presetID: presetID, fromDropzone: true)
                } else {
                    ids += vm.addAndCompressWithActivePreset(local, force: force, fromDropzone: true)
                }
            }
            if !remote.isEmpty {
                ids += vm.queueRemoteDownload(
                    urls: remote,
                    force: force,
                    presetID: presetID ?? UUID(uuidString: self.prefs.activePresetID),
                    fromDropzone: true
                )
            }
            let wanted = Set(ids)
            let items = vm.items.filter { wanted.contains($0.id) }
            // Nothing new: unsupported files, or all of them already in the queue.
            guard !items.isEmpty else { self.hide(); return }
            self.track(items)
        }
        return true
    }

    private func track(_ items: [CompressionItem]) {
        results = items
        originalSizes = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.originalSize) })
        // `$status` fires before the new value lands; look once the change has settled.
        statusWatch = Publishers.MergeMany(items.map { $0.$status.map { _ in () } })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                // The view reads progress off the rows; let it know one moved.
                self?.objectWillChange.send()
                self?.checkFinished()
            }
        checkFinished()
    }

    private func checkFinished() {
        guard stage == .working, !results.isEmpty,
              results.allSatisfy({ $0.status.isTerminal }) else { return }
        statusWatch = nil
        stage = .done
        if !isHovering { scheduleHide(after: Self.resultsLinger) }
    }

    // MARK: - Actions from the view

    func reveal(_ item: CompressionItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.outputURL ?? item.sourceURL])
    }

    func openMainWindow() {
        hide()
        DockPresenceManager.showMainWindow()
    }

    func dismiss() { hide() }

    // MARK: - Panel

    private func showPanel() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        positionPanel()
        panel.orderFrontRegardless()
    }

    private func makePanel() -> FloatingDropzonePanel {
        let panel = FloatingDropzonePanel(contentRect: NSRect(origin: .zero, size: Self.collapsedSize))
        let root = FloatingDropzoneView(controller: self)
            .environmentObject(prefs)
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        panel.contentView = host
        return panel
    }

    /// Pins the panel's corner to the chosen corner of the screen the pointer is on.
    private func positionPanel() {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = isExpanded || stage == .working || stage == .done ? Self.expandedSize : Self.collapsedSize
        let x = corner.isLeft ? visible.minX + Self.edgeInset : visible.maxX - Self.edgeInset - size.width
        let y = corner.isTop ? visible.maxY - Self.edgeInset - size.height : visible.minY + Self.edgeInset
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }

    /// Grows the window before the view animates open, and shrinks it only after the view has
    /// animated closed, so nothing gets clipped. The view is pinned to the same corner as the
    /// window, so a resize never shows.
    private func setExpanded(_ expanded: Bool) {
        guard expanded != isExpanded else { return }
        resizeTask?.cancel()
        if expanded {
            isExpanded = true
            resizePanelKeepingCorner(to: Self.expandedSize)
        } else {
            isExpanded = false
            resizeTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(Self.tuckDuration))
                guard let self, !Task.isCancelled, !self.isExpanded, self.stage == .dragging else { return }
                self.resizePanelKeepingCorner(to: Self.collapsedSize)
            }
        }
    }

    private func resizePanelKeepingCorner(to size: CGSize) {
        guard let panel else { return }
        let f = panel.frame
        let x = corner.isLeft ? f.minX : f.maxX - size.width
        let y = corner.isTop ? f.maxY - size.height : f.minY
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }

    private func scheduleHide(after delay: TimeInterval) {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled else { return }
            self.hide()
        }
    }

    private func cancelPendingHide() {
        hideTask?.cancel()
        hideTask = nil
    }

    /// Tucks the dropzone back into its corner, then takes the window off screen.
    private func hide(animated: Bool = true) {
        cancelPendingHide()
        resizeTask?.cancel()
        statusWatch = nil
        stage = .hidden
        isExpanded = false
        proximity = 0
        let close = { [weak self] in
            guard let self, self.stage == .hidden else { return }
            self.panel?.orderOut(nil)
            self.dragged = nil
        }
        if animated {
            hideTask = Task {
                try? await Task.sleep(for: .seconds(Self.tuckDuration))
                guard !Task.isCancelled else { return }
                close()
            }
        } else {
            close()
        }
    }
}

// MARK: - Panel window

/// Borderless, never activates Dinky, floats over full-screen apps on every Space. It can't become
/// main, so it never counts as an open window for the Dock icon logic in `DockPresenceManager`.
final class FloatingDropzonePanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        // The glass draws its own shadow; a window shadow would outline the transparent margin.
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
