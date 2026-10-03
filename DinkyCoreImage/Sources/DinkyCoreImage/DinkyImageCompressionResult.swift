import DinkyCoreShared
import Foundation

public struct DinkyImageCompressionResult: Sendable {
    public let outputURL: URL
    public let originalSize: Int64
    public let outputSize: Int64
    public let detectedContentType: ContentType?
    public var usedFirstFrameOnly: Bool = false
    /// Applied AVIF chroma subsampling (`420`, `422`, `444`, or nil when not AVIF).
    public var appliedChromaSubsampling: String? = nil
    /// True when WebP lossless mode was used.
    public var appliedWebpLossless: Bool = false
    /// Applied PNG mode (`lossless` or `optimized`).
    public var appliedPngOutputMode: String? = nil
    /// Set when the image was downscaled to fit a width limit.
    public var resize: ImageResizeInfo? = nil
    /// Set when the output would have overwritten the source: the encode is at `outputURL` (a temp
    /// file) and belongs at this path — the source's — if the caller keeps it.
    public var stagedDestinationURL: URL? = nil

    public init(
        outputURL: URL,
        originalSize: Int64,
        outputSize: Int64,
        detectedContentType: ContentType? = nil,
        usedFirstFrameOnly: Bool = false,
        appliedChromaSubsampling: String? = nil,
        appliedWebpLossless: Bool = false,
        appliedPngOutputMode: String? = nil,
        resize: ImageResizeInfo? = nil,
        stagedDestinationURL: URL? = nil
    ) {
        self.outputURL = outputURL
        self.originalSize = originalSize
        self.outputSize = outputSize
        self.detectedContentType = detectedContentType
        self.usedFirstFrameOnly = usedFirstFrameOnly
        self.appliedChromaSubsampling = appliedChromaSubsampling
        self.appliedWebpLossless = appliedWebpLossless
        self.appliedPngOutputMode = appliedPngOutputMode
        self.resize = resize
        self.stagedDestinationURL = stagedDestinationURL
    }
}
