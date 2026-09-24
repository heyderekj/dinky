import Foundation

/// 2.13.1 gave Watch Folders their own originals setting defaulting to Trash. People who already
/// had a watch folder were previously following the general Originals setting (default: keep), so
/// updating silently started moving their originals to the Trash. On the first launch after this
/// migration ships, anyone who already had a watch folder gets the watch setting copied from the
/// general one; people who never used watch folders keep the Trash default for when they do.
public enum WatchOriginalsMigration {
    public static let doneKey = "watchOriginalsActionMigrated"
    static let watchOriginalsKey = "watchOriginalsAction"
    static let originalsKey = "originalsAction"

    public static func runIfNeeded(_ defaults: UserDefaults) {
        guard !defaults.bool(forKey: doneKey) else { return }
        defaults.set(true, forKey: doneKey)
        // Someone who already picked a watch setting in 2.13.1 made a choice — leave it.
        guard defaults.object(forKey: watchOriginalsKey) == nil, hadWatchFolder(defaults) else { return }
        let general = defaults.string(forKey: originalsKey) ?? OriginalsAction.keep.rawValue
        defaults.set(general, forKey: watchOriginalsKey)
    }

    private static func hadWatchFolder(_ defaults: UserDefaults) -> Bool {
        if defaults.bool(forKey: "folderWatchEnabled") { return true }
        if let path = defaults.string(forKey: "watchedFolderPath"), !path.isEmpty { return true }
        guard let data = defaults.data(forKey: "savedPresetsData"),
              let presets = try? JSONDecoder().decode([CompressionPreset].self, from: data)
        else { return false }
        return presets.contains { $0.watchFolderEnabled }
    }
}
