import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
    }

    // MARK: - Open with Dinky / drag onto Dock icon

    func application(_ application: NSApplication, open urls: [URL]) {
        let images = imageURLs(from: urls)
        guard !images.isEmpty else { return }
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .dinkyOpenFiles, object: images)
    }

    // MARK: - Compress from Clipboard menu command

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
            .urlReadingContentsConformToTypes: imageUTIs
        ]
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: opts) as? [URL],
              !urls.isEmpty else { return }
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .dinkyOpenFiles, object: urls)
    }

    // MARK: - Helpers

    private let imageUTIs = [
        "public.jpeg", "public.png", "org.webmproject.webp",
        "public.avif", "public.tiff", "com.microsoft.bmp"
    ]

    private func imageURLs(from urls: [URL]) -> [URL] {
        let exts = Set(["jpg","jpeg","png","webp","avif","tiff","bmp"])
        return urls.filter { exts.contains($0.pathExtension.lowercased()) }
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
