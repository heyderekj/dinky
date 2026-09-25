import Foundation

/// Whether a finished encode is worth keeping. Decided *before* anything happens to the original,
/// so a result that's thrown away never costs the user their source file.
public enum CompressionOutcome: Equatable, Sendable {
    case keep
    /// Output wasn't smaller than the original.
    case zeroGain
    /// Smaller, but by less than the "Minimum savings" setting.
    case skipped(savedPercent: Double)
}

public enum CompressionOutcomeDecider {
    /// - Parameter didResize: The image was downscaled to fit a width limit. The user asked for those
    ///   dimensions, so the result is kept even when the bytes didn't shrink.
    public static func decide(
        originalBytes: Int64,
        outputBytes: Int64,
        minimumSavingsPercent: Int,
        forced: Bool,
        didResize: Bool = false
    ) -> CompressionOutcome {
        if didResize { return .keep }
        if outputBytes >= originalBytes { return .zeroGain }
        let saved = originalBytes > 0 ? Double(originalBytes - outputBytes) / Double(originalBytes) : 0
        if minimumSavingsPercent > 0, saved < Double(minimumSavingsPercent) / 100.0, !forced {
            return .skipped(savedPercent: saved * 100)
        }
        return .keep
    }
}
