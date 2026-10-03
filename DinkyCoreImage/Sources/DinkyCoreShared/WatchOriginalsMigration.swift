import Foundation

/// What happens to originals a watch folder picked up. By default it follows the general
/// Original Files setting; an explicit choice overrides it for watch folders only.
public enum WatchOriginalsPolicy: Hashable, Sendable {
    case followGeneral
    case explicit(OriginalsAction)

    public static let followRawValue = "followOutput"

    /// Unset or unrecognised values follow the general setting.
    public init(storedRawValue: String?) {
        if let raw = storedRawValue, let action = OriginalsAction(rawValue: raw) {
            self = .explicit(action)
        } else {
            self = .followGeneral
        }
    }

    public var storedRawValue: String {
        switch self {
        case .followGeneral: return Self.followRawValue
        case .explicit(let action): return action.rawValue
        }
    }

    public func resolved(general: OriginalsAction) -> OriginalsAction {
        switch self {
        case .followGeneral: return general
        case .explicit(let action): return action
        }
    }
}

/// 2.13.1 gave Watch Folders their own originals setting defaulting to Trash. People who already
/// had a watch folder were previously following the general Originals setting (default: keep), so
/// updating silently started moving their originals to the Trash. On the first launch after this
/// migration ships, anyone who already had a watch folder gets the watch setting copied from the
/// general one; people who never used watch folders keep the Trash default for when they do.
public enum WatchOriginalsMigration {
    public static let doneKey = "watchOriginalsActionMigrated"
    public static let followDoneKey = "watchOriginalsFollowMigrated"
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

    /// 2.14.1: an unset watch setting now follows the general one instead of meaning Trash, so a
    /// user who says "originals stay where they are" gets that everywhere. A watch value equal to the
    /// general one (what `runIfNeeded` copied) becomes "follow" too; a different value was a choice.
    /// Run after `runIfNeeded`.
    public static func runFollowGeneralMigrationIfNeeded(_ defaults: UserDefaults) {
        guard !defaults.bool(forKey: followDoneKey) else { return }
        defaults.set(true, forKey: followDoneKey)
        guard let watch = defaults.string(forKey: watchOriginalsKey) else { return }
        let general = defaults.string(forKey: originalsKey) ?? OriginalsAction.keep.rawValue
        if watch == general {
            defaults.removeObject(forKey: watchOriginalsKey)
        }
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
