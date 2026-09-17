import DinkyCoreShared
import Foundation

public struct DinkyImageCompressionResult: Sendable {
    public let outputURL: URL
    public let originalSize: Int64
    public let outputSize: Int64
    public var originalRecoveryURL: URL? = nil
    public let detectedContentType: ContentType?
    public var usedFirstFrameOnly: Bool = false
    /// Applied AVIF chroma subsampling (`420`, `422`, `444`, or nil when not AVIF).
    public var appliedChromaSubsampling: String? = nil
    /// True when WebP lossless mode was used.
    public var appliedWebpLossless: Bool = false
    /// Applied PNG mode (`lossless` or `optimized`).
    public var appliedPngOutputMode: String? = nil

    public init(
        outputURL: URL,
        originalSize: Int64,
        outputSize: Int64,
        originalRecoveryURL: URL? = nil,
        detectedContentType: ContentType? = nil,
        usedFirstFrameOnly: Bool = false,
        appliedChromaSubsampling: String? = nil,
        appliedWebpLossless: Bool = false,
        appliedPngOutputMode: String? = nil
    ) {
        self.outputURL = outputURL
        self.originalSize = originalSize
        self.outputSize = outputSize
        self.originalRecoveryURL = originalRecoveryURL
        self.detectedContentType = detectedContentType
        self.usedFirstFrameOnly = usedFirstFrameOnly
        self.appliedChromaSubsampling = appliedChromaSubsampling
        self.appliedWebpLossless = appliedWebpLossless
        self.appliedPngOutputMode = appliedPngOutputMode
    }
}
