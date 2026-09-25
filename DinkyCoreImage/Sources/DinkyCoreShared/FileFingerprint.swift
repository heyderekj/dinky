import Foundation

/// Cheap "is this still the same file?" check: size plus content modification date.
public struct FileFingerprint: Codable, Equatable, Hashable, Sendable {
    public let size: Int64
    public let modificationDate: Date?

    public init(size: Int64, modificationDate: Date?) {
        self.size = size
        self.modificationDate = modificationDate
    }

    public init?(url: URL) {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let size = values.fileSize
        else { return nil }
        self.init(size: Int64(size), modificationDate: values.contentModificationDate)
    }
}
