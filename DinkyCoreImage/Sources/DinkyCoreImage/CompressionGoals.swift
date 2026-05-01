import Foundation

public struct CompressionGoals: Sendable {
    public var maxWidth: Int?
    public var maxFileSizeKB: Int?

    public init(maxWidth: Int? = nil, maxFileSizeKB: Int? = nil) {
        self.maxWidth = maxWidth
        self.maxFileSizeKB = maxFileSizeKB
    }
}
