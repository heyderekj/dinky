import Foundation

/// Picks the rows that belong to one compression batch. The queue can still hold rows from earlier
/// batches (auto-clear off, or a menu-bar-only session where the list is never cleared), and those
/// must not be counted again in a new batch's summary, history entry, or lifetime savings.
public enum BatchScope {
    /// - Parameter ids: The batch's item ids, or nil for summaries saved before batches recorded
    ///   their items — those keep the old behaviour of using every row.
    public static func items<T>(_ items: [T], in ids: Set<UUID>?, id: (T) -> UUID) -> [T] {
        guard let ids else { return items }
        return items.filter { ids.contains(id($0)) }
    }
}
