import AppKit
import Foundation

enum ClipboardImport {
    /// Every copied file Dinky can compress (folders expanded).
    case localFiles([URL])
    case remoteURL(URL)
}

enum ClipboardImporter {
    /// Same rules as drag-and-drop: local file, raw image bytes, or an `https` link to a direct media file.
    static func importFromClipboard() -> ClipboardImport? {
        let pb = NSPasteboard.general

        // Prefer a file URL (user did Copy in Finder) — no re-encoding needed
        let fileOpts: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: fileOpts) as? [URL] {
            let files = urls.flatMap(DroppedItemsReader.expandAndFilter)
            if !files.isEmpty { return .localFiles(files) }
        }

        // Fallback: raw image bytes (screenshot, browser copy, etc.)
        // Prefer PNG over TIFF — smaller temp file, lossless, widely supported by our encoders
        if let data = pb.data(forType: .png) ?? pb.data(forType: .tiff) {
            let ext = pb.data(forType: .png) != nil ? "png" : "tiff"
            // A readable name, since the result is named after it ("Pasted image … -dinky.webp"),
            // in its own folder so two pastes in the same second can't collide.
            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("dinky_paste_\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let tmp = folder
                .appendingPathComponent(pastedImageName())
                .appendingPathExtension(ext)
            try? data.write(to: tmp, options: .atomic)
            return .localFiles([tmp])
        }

        // `NSURL` on pasteboard (Safari address bar, etc.) — may be `https` or `file`
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [:]) as? [URL], let u = urls.first {
            if u.isFileURL, MediaTypeDetector.detect(u) != nil {
                return .localFiles([u])
            }
            if let s = u.scheme?.lowercased(), s == "http" || s == "https" {
                return .remoteURL(u)
            }
        }

        // Plain text URL (first line only)
        if let s = pb.string(forType: .string),
           let url = firstHTTPURL(in: s) {
            return .remoteURL(url)
        }

        return nil
    }

    /// "Pasted image 2026-10-29 at 14.02.11", like macOS screenshot names.
    private static func pastedImageName() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return String.localizedStringWithFormat(
            String(localized: "Pasted image %@", comment: "File name for an image pasted from the clipboard; argument is the date and time."),
            f.string(from: Date())
        )
    }

    /// First `http(s)` URL on the first line of `text` (paste one link at a time).
    static func firstHTTPURL(in text: String) -> URL? {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let u = URL(string: trimmed), let s = u.scheme?.lowercased(), s == "http" || s == "https" else { return nil }
        return u
    }

    /// True when `importFromClipboard()` would return a value.
    static func isClipboardImportable() -> Bool {
        importFromClipboard() != nil
    }
}
