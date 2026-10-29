import AppKit
import DinkyCoreShared

/// Notices when files Dinky can compress are being dragged in any app, so the floating dropzone
/// can show up before the drop. Global mouse monitors need no Accessibility permission; the
/// system drag pasteboard says whether the drag carries files.
///
/// Global monitors never see Dinky's own events, so dragging rows or results out of Dinky
/// doesn't wake the dropzone.
@MainActor
final class FileDragWatcher {

    struct DraggedFiles: Equatable {
        /// Media found among the dragged files, in a stable order (image, video, audio, PDF).
        var mediaTypes: [MediaType]
        var count: Int
        /// A folder is in the drag; its contents aren't read until the drop.
        var includesFolder: Bool
    }

    enum Event {
        case began(DraggedFiles)
        case moved(NSPoint)
        case ended
    }

    var onEvent: ((Event) -> Void)?

    private enum State {
        case idle
        /// Mouse is down; waiting to see whether a drag of files starts. `checks` counts drag
        /// events seen without the drag pasteboard changing.
        case pressed(changeCount: Int, checks: Int)
        /// A drag started that isn't ours to care about (text, a window, a non-media file).
        case ignored
        case dragging
    }

    private var state: State = .idle
    private var monitors: [Any] = []
    private var lastMoveSent: TimeInterval = 0
    /// A drag can end without a mouse-up reaching us (e.g. dropped on a window that ate it);
    /// this checks the button state while a drag is live.
    private var watchdog: Timer?

    var isRunning: Bool { !monitors.isEmpty }

    private static let maxChecks = 8

    func start() {
        guard monitors.isEmpty else { return }
        if let m = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp],
            handler: { [weak self] event in
                let type = event.type
                MainActor.assumeIsolated { self?.handle(type) }
            }
        ) {
            monitors.append(m)
        }
        // A drop onto the dropzone itself can deliver the mouse-up to Dinky, where the global
        // monitor can't see it.
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp], handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(.leftMouseUp) }
            return event
        }) {
            monitors.append(m)
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        endDrag()
        state = .idle
    }

    private func handle(_ type: NSEvent.EventType) {
        switch type {
        case .leftMouseDown:
            state = .pressed(changeCount: NSPasteboard(name: .drag).changeCount, checks: 0)
        case .leftMouseDragged:
            switch state {
            case .pressed(let startCount, let checks):
                let pb = NSPasteboard(name: .drag)
                // The source writes the drag pasteboard a few points into the drag, not on mouse-down.
                // Still unchanged after a handful of events, it's a window move or a text selection:
                // stop asking the pasteboard (a cross-process call) on every mouse event.
                guard pb.changeCount != startCount else {
                    state = checks >= Self.maxChecks ? .ignored : .pressed(changeCount: startCount, checks: checks + 1)
                    return
                }
                if let files = Self.draggedFiles(on: pb) {
                    state = .dragging
                    startWatchdog()
                    onEvent?(.began(files))
                } else {
                    state = .ignored
                }
            case .dragging:
                let now = ProcessInfo.processInfo.systemUptime
                guard now - lastMoveSent > 1.0 / 30 else { return }
                lastMoveSent = now
                onEvent?(.moved(NSEvent.mouseLocation))
            case .idle, .ignored:
                break
            }
        case .leftMouseUp:
            if case .dragging = state { endDrag() }
            state = .idle
        default:
            break
        }
    }

    private func endDrag() {
        watchdog?.invalidate()
        watchdog = nil
        guard case .dragging = state else { return }
        state = .idle
        onEvent?(.ended)
    }

    private func startWatchdog() {
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if NSEvent.pressedMouseButtons & 1 == 0 { self.endDrag() }
            }
        }
    }

    /// `nil` unless the drag holds at least one file Dinky can compress (or a folder that might).
    private static func draggedFiles(on pb: NSPasteboard) -> DraggedFiles? {
        guard let urls = pb.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty else { return nil }

        var found = Set<MediaType>()
        var count = 0
        var includesFolder = false
        for url in urls {
            if let media = MediaTypeDetector.detect(url) {
                found.insert(media)
                count += 1
            } else if let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey]),
                      values.isDirectory == true, values.isPackage != true {
                includesFolder = true
            }
        }
        guard count > 0 || includesFolder else { return nil }
        let order: [MediaType] = [.image, .video, .audio, .pdf]
        return DraggedFiles(mediaTypes: order.filter(found.contains), count: count, includesFolder: includesFolder)
    }
}
