import Foundation

/// 2.17: a first drag-and-drop just compresses. New installs no longer get the confirmation
/// sheet, Finder opening on its own, or the batch summary after every batch (it still appears when
/// something failed or was skipped). People updating keep what they had: on the first launch with
/// this migration, anyone who has used Dinky before gets the old defaults written explicitly for
/// any of these they never changed. Run before other migrations, which write keys on first launch.
public enum FirstDropDefaultsMigration {
    public static let doneKey = "firstDropDefaultsMigrated"

    /// Settings whose default changed from `true` to `false`.
    static let changedKeys = ["confirmBeforeEveryCompression", "openFolderWhenDone", "showBatchSummaryDialog"]

    /// Any of these existing means Dinky ran before (`watchOriginalsActionMigrated` is written on
    /// every launch since 2.13.1).
    static let priorUseKeys = [
        "watchOriginalsActionMigrated", "lifetimeSavedBytesRaw", "sessionHistoryData",
        "savedPresetsData", "concurrentTasks", "selectedFormat",
    ]

    public static func runIfNeeded(_ defaults: UserDefaults) {
        guard !defaults.bool(forKey: doneKey) else { return }
        defaults.set(true, forKey: doneKey)
        guard priorUseKeys.contains(where: { defaults.object(forKey: $0) != nil }) else { return }
        for key in changedKeys where defaults.object(forKey: key) == nil {
            defaults.set(true, forKey: key)
        }
    }
}
