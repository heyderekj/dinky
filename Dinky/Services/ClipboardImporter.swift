import AppKit
import Foundation

enum ClipboardImporter {
    static func importFromClipboard() -> URL? {
        let pb = NSPasteboard.general

        // Prefer a file URL (user did Copy in Finder) — no re-encoding needed
        let fileOpts: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: fileOpts) as? [URL],
           let url = urls.first,
           ["jpg", "jpeg", "png", "webp", "avif", "tiff", "bmp"]
               .contains(url.pathExtension.lowercased()) {
            return url
        }

        // Fallback: raw image bytes (screenshot, browser copy, etc.)
        // Prefer PNG over TIFF — smaller temp file, lossless, widely supported by our encoders
        guard let data = pb.data(forType: .png) ?? pb.data(forType: .tiff) else { return nil }
        let ext = pb.data(forType: .png) != nil ? "png" : "tiff"
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("dinky_paste_\(UUID().uuidString)")
            .appendingPathExtension(ext)
        try? data.write(to: tmp, options: .atomic)
        return tmp
    }

    static func isClipboardImage() -> Bool {
        let pb = NSPasteboard.general
        let fileOpts: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: fileOpts) as? [URL],
           let url = urls.first,
           ["jpg", "jpeg", "png", "webp", "avif", "tiff", "bmp"]
               .contains(url.pathExtension.lowercased()) {
            return true
        }
        return pb.data(forType: .png) != nil || pb.data(forType: .tiff) != nil
    }
}
