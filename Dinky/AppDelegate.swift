import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var globalPasteHotkeyObserver: NSObjectProtocol?
    private var dockPresenceObserver: NSObjectProtocol?
    private var floatingDropzoneObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        migratePDFMaxFileSizeIfNeeded()
        // Builds preferences + the content model now, so watch folders start on a headless
        // launch too — SwiftUI would otherwise not create them until a window is shown.
        _ = DinkyRootModel.shared
        DiagnosticsReporter.shared.startMonitoring()
        UNUserNotificationCenter.current().delegate = self
        // Suppression first, so the launch-time policy check ignores the window it's about to hide.
        DockPresenceManager.scheduleSuppressInitialWindowIfNeeded()
        DockPresenceManager.applyFromDefaults()
        DockPresenceManager.startTrackingWindows()
        GlobalHotkeyManager.shared.syncFromDefaults()
        globalPasteHotkeyObserver = NotificationCenter.default.addObserver(
            forName: .dinkyGlobalPasteHotkeyChanged,
            object: nil,
            queue: .main
        ) { _ in
            GlobalHotkeyManager.shared.syncFromDefaults()
        }
        FloatingDropzoneController.shared.syncFromDefaults()
        floatingDropzoneObserver = NotificationCenter.default.addObserver(
            forName: .dinkyFloatingDropzoneChanged,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { FloatingDropzoneController.shared.syncFromDefaults() }
        }
        dockPresenceObserver = NotificationCenter.default.addObserver(
            forName: .dinkyDockPresenceChanged,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { DockPresenceManager.applyFromDefaults() }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        DockPresenceManager.showMainWindow()
        // Handled: AppKit's default reopen would have SwiftUI open a second window alongside it.
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { DinkyRootModel.shared.contentVM.flushSelfWrittenOutputs() }
        DiagnosticsReporter.shared.clearSentinel()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let runTeardown = {
            var iterations = 0
            while iterations < 16, NSApp.modalWindow != nil {
                NSApp.abortModal()
                iterations += 1
            }
            NotificationCenter.default.post(name: .dinkyPrepareQuit, object: nil)
            DispatchQueue.main.async {
                DispatchQueue.main.async {
                    NSApp.reply(toApplicationShouldTerminate: true)
                }
            }
        }
        if Thread.isMainThread {
            runTeardown()
        } else {
            DispatchQueue.main.async(execute: runTeardown)
        }
        return .terminateLater
    }

    // MARK: - Open with Dinky / drag onto Dock icon

    func application(_ application: NSApplication, open urls: [URL]) {
        let accepted = acceptedURLs(from: urls)
        guard !accepted.isEmpty else { return }
        DockPresenceManager.cancelInitialWindowSuppression()
        DockPresenceManager.showMainWindow {
            NotificationCenter.default.post(name: .dinkyOpenFiles, object: accepted)
        }
    }

    // MARK: - Clipboard Compress menu command

    @MainActor @objc func compressFromClipboard(_ sender: Any?) {
        DockPresenceManager.showMainWindow {
            NotificationCenter.default.post(name: .dinkyPasteClipboard, object: nil)
        }
    }

    // MARK: - Right-click → Services → Compress with Dinky

    @MainActor @objc func compressWithDinky(
        _ pasteboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        let opts: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let selected = pasteboard.readObjects(forClasses: [NSURL.self], options: opts) as? [URL] else { return }
        // Folders and audio too, same as dropping on the window.
        let urls = acceptedURLs(from: selected)
        guard !urls.isEmpty else { return }
        DockPresenceManager.cancelInitialWindowSuppression()
        DockPresenceManager.showMainWindow {
            NotificationCenter.default.post(name: .dinkyOpenFiles, object: urls)
        }
    }

    // MARK: - Helpers

    /// Files Dinky can compress, with folders expanded to the files inside them.
    private func acceptedURLs(from urls: [URL]) -> [URL] {
        urls.flatMap(DroppedItemsReader.expandAndFilter)
    }

    /// Older builds allowed sub‑MB targets; clamp global PDF max size to 5–25 MB to match current presets.
    private func migratePDFMaxFileSizeIfNeeded() {
        let key = "pdfMaxFileSizeKB"
        let v = UserDefaults.standard.integer(forKey: key)
        guard v != 0 else { return }
        let clamped = clampPDFMaxFileSizeKB(v)
        if clamped != v {
            UserDefaults.standard.set(clamped, forKey: key)
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension AppDelegate: UNUserNotificationCenterDelegate {
    // Allow banners to appear even when Dinky is in the foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
