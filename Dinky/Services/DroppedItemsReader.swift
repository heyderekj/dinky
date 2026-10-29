import Foundation
import DinkyCoreShared
import UniformTypeIdentifiers

/// Turns dropped item providers into compressible files and `http(s)` links. Shared by the main
/// window's drop zone and the floating dropzone so both accept exactly the same things.
enum DroppedItemsReader {

    /// Calls `completion` on the main queue with local files (folders expanded, unsupported files
    /// dropped) and remote media links.
    static func read(_ providers: [NSItemProvider], completion: @escaping (_ local: [URL], _ remote: [URL]) -> Void) {
        var collected: [URL] = []
        var remoteURLs: [URL] = []
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
            completion(collected, remoteURLs)
        }
    }

    /// A file stays if Dinky can compress it; a folder becomes every compressible file inside it.
    static func expandAndFilter(_ url: URL) -> [URL] {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return [] }
        let urls: [URL] = isDir.boolValue
            ? (FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)?
                .compactMap { $0 as? URL } ?? [])
            : [url]
        return urls.filter { MediaTypeDetector.detect($0) != nil }
    }
}
