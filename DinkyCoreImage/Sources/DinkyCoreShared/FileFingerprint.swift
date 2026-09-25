import Foundation

/// Cheap "is this still the same file?" check: size, content modification date, and when it was
/// added to its folder — so repeat filesystem events for one arrival match, but copying the same
/// file in again (same size and dates, new arrival) counts as new.
public struct FileFingerprint: Codable, Equatable, Hashable, Sendable {
    public let size: Int64
    public let modificationDate: Date?
    public let addedDate: Date?

    public init(size: Int64, modificationDate: Date?, addedDate: Date? = nil) {
        self.size = size
        self.modificationDate = modificationDate
        self.addedDate = addedDate
    }

    public init?(url: URL) {
        var fresh = url
        fresh.removeAllCachedResourceValues()
        guard let values = try? fresh.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .addedToDirectoryDateKey]),
              let size = values.fileSize
        else { return nil }
        self.init(size: Int64(size), modificationDate: values.contentModificationDate, addedDate: values.addedToDirectoryDate)
    }
}
