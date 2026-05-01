import Foundation

/// What to do with the original file after a successful compress.
public enum OriginalsAction: String, Sendable, Codable, CaseIterable, Identifiable {
    case keep
    case trash
    case backup
    public var id: String { rawValue }
}

/// How to pick a new filename when the computed output path is already occupied.
public enum CollisionNamingStyle: String, Sendable, Codable, CaseIterable, Identifiable {
    case finderDuplicate
    case finderNumbered
    case custom
    public var id: String { rawValue }
}
