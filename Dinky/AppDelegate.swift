import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var globalPasteHotkeyObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        migratePDFMaxFileSizeIfNeeded()
        DiagnosticsReporter.shared.startMonitoring()
        UNUserNotificationCenter.current().delegate = self
        GlobalHotkeyManager.shared.syncFromDefaults()
        globalPasteHotkeyObserver = NotificationCenter.default.addObserver(
            forName: .dinkyGlobalPasteHotkeyChanged,
            object: nil,
            queue: .main
        ) { _ in
            GlobalHotkeyManager.shared.syncFromDefaults()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
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
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .dinkyOpenFiles, object: accepted)
    }

    // MARK: - Clipboard Compress menu command

    @objc func compressFromClipboard(_ sender: Any?) {
        NotificationCenter.default.post(name: .dinkyPasteClipboard, object: nil)
    }

    // MARK: - Right-click → Services → Compress with Dinky

    @objc func compressWithDinky(
        _ pasteboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        let opts: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: acceptedUTIs
        ]
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: opts) as? [URL],
              !urls.isEmpty else { return }
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .dinkyOpenFiles, object: urls)
    }

    // MARK: - Helpers

    private let acceptedUTIs = [
        "public.jpeg", "public.png", "org.webmproject.webp",
        "public.avif", "public.tiff", "com.microsoft.bmp",
        "public.heic", "public.heif",
        "public.gif", "com.compuserve.gif",
        "com.adobe.pdf",
        "public.mpeg-4", "com.apple.quicktime-movie", "public.m4v-video",
        "public.avi",
    ]

    private func acceptedURLs(from urls: [URL]) -> [URL] {
        urls.filter { MediaTypeDetector.detect($0) != nil }
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
