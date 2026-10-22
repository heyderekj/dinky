import DinkyCoreShared
import Foundation

public struct CompressionGoals: Sendable {
    public var maxWidth: Int?
    public var maxFileSizeKB: Int?
    /// Percent of the original width and height, applied before ``maxWidth`` (which still caps the scaled result).
    public var scalePercent: Int?

    /// Allowed scale percentages. Dinky only shrinks, so 100% is the ceiling.
    public static let scalePercentRange: ClosedRange<Int> = 1...100

    public static func clampedScalePercent(_ percent: Int) -> Int {
        min(scalePercentRange.upperBound, max(scalePercentRange.lowerBound, percent))
    }

    public init(maxWidth: Int? = nil, maxFileSizeKB: Int? = nil, scalePercent: Int? = nil) {
        self.maxWidth = maxWidth
        self.maxFileSizeKB = maxFileSizeKB
        self.scalePercent = scalePercent.map(Self.clampedScalePercent)
    }

    /// True when these goals may change pixel dimensions.
    public var changesDimensions: Bool {
        maxWidth != nil || (scalePercent.map { $0 < 100 } ?? false)
    }

    /// Output pixel size for an image of `width`×`height` (display orientation), or nil when unchanged.
    /// Percentage scaling runs first; the max width then caps the result, keeping its proportions.
    public func outputPixelSize(width: Int, height: Int) -> (width: Int, height: Int)? {
        guard width > 0, height > 0 else { return nil }
        var outW = width
        var outH = height
        if let scalePercent {
            outW = max(1, Int((Double(width) * Double(scalePercent) / 100).rounded()))
            outH = max(1, Int((Double(height) * Double(scalePercent) / 100).rounded()))
        }
        if let maxWidth, maxWidth > 0, outW > maxWidth {
            outH = max(1, Int((Double(outH) * Double(maxWidth) / Double(outW)).rounded()))
            outW = maxWidth
        }
        guard outW != width || outH != height else { return nil }
        return (outW, outH)
    }
}
