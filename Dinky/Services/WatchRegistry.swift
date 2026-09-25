import Foundation

/// Routes a file URL to either the global sidebar pipeline or a preset snapshot pipeline.
enum WatchPipeline: Equatable {
    case global
    case preset(UUID)
}

enum WatchFolderPathResolver {

    static func normalizedPath(_ path: String) -> String {
        WatchPaths.normalized(path)
    }

    /// Prefer resolving the security-scoped bookmark (survives renames); fall back to `storedPath` only when it still exists as a directory.
    static func resolvedWatchDirectoryPath(bookmark: Data, storedPath: String) -> String? {
        if !bookmark.isEmpty {
            var stale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) {
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                    return normalizedPath(url.path)
                }
            }
        }
        let s = normalizedPath(storedPath)
        guard !s.isEmpty else { return nil }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: s, isDirectory: &isDir), isDir.boolValue else { return nil }
        return s
    }

    /// Whether `file` sits under `root` (or equals it). Both paths are standardized.
    static func file(_ file: URL, isUnderRoot root: String) -> Bool {
        WatchPaths.path(file.path, isUnder: root)
    }
}

/// Builds routing rules from `DinkyPreferences`: global watch + presets with unique paths.
/// If the same path is both global and unique-preset, **preset wins** (checked first).
struct WatchPipelineRegistry {
    let globalPath: String?
    let presetPaths: [(UUID, String)]
    /// Watch folders that are turned on but can't be found right now — e.g. on a drive or share
    /// that isn't mounted yet after a restart.
    let unresolvedCount: Int

    init(prefs: DinkyPreferences) {
        let gp: String? = prefs.folderWatchEnabled
            ? WatchFolderPathResolver.resolvedWatchDirectoryPath(
                bookmark: prefs.watchedFolderBookmark,
                storedPath: prefs.watchedFolderPath
            )
            : nil
        var unresolved = 0
        if prefs.folderWatchEnabled, gp == nil, !(prefs.watchedFolderPath.isEmpty && prefs.watchedFolderBookmark.isEmpty) {
            unresolved += 1
        }
        var presets: [(UUID, String)] = []
        for preset in prefs.savedPresets where preset.watchFolderEnabled && preset.watchFolderModeRaw == "unique" {
            guard let raw = WatchFolderPathResolver.resolvedWatchDirectoryPath(
                bookmark: preset.watchFolderBookmark,
                storedPath: preset.watchFolderPath
            ) else {
                if !(preset.watchFolderPath.isEmpty && preset.watchFolderBookmark.isEmpty) { unresolved += 1 }
                continue
            }
            presets.append((preset.id, raw))
        }
        // Longest root first; same-length ties keep array order (earlier preset wins).
        presets.sort { $0.1.count > $1.1.count }
        self.globalPath = gp
        self.presetPaths = presets
        self.unresolvedCount = unresolved
    }

    /// Longest matching preset root wins (list is sorted); else global if it matches.
    func pipeline(for file: URL) -> WatchPipeline {
        for (id, root) in presetPaths where WatchFolderPathResolver.file(file, isUnderRoot: root) {
            return .preset(id)
        }
        if let g = globalPath, WatchFolderPathResolver.file(file, isUnderRoot: g) {
            return .global
        }
        return .global
    }

    /// Distinct directory paths for FSEvents (deduped).
    var watchedRootPaths: [String] {
        Self.allWatchedPaths(globalPath: globalPath, presetPaths: presetPaths)
    }

    static func allWatchedPaths(globalPath: String?, presetPaths: [(UUID, String)]) -> [String] {
        var paths: [String] = []
        var norm = Set<String>()
        for (_, root) in presetPaths {
            let n = WatchFolderPathResolver.normalizedPath(root)
            guard !n.isEmpty else { continue }
            if norm.insert(n).inserted { paths.append(root) }
        }
        if let g = globalPath, !g.isEmpty {
            let n = WatchFolderPathResolver.normalizedPath(g)
            if norm.insert(n).inserted { paths.append(g) }
        }
        return paths
    }
}
