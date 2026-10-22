import Foundation

/// Pixel dimensions before and after an image was resized (percentage scale and/or width limit).
public struct ImageResizeInfo: Codable, Equatable, Hashable, Sendable {
    public let originalWidth: Int
    public let originalHeight: Int
    public let outputWidth: Int
    public let outputHeight: Int

    public init(originalWidth: Int, originalHeight: Int, outputWidth: Int, outputHeight: Int) {
        self.originalWidth = originalWidth
        self.originalHeight = originalHeight
        self.outputWidth = outputWidth
        self.outputHeight = outputHeight
    }
}
