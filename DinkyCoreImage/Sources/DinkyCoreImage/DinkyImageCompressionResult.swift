import Foundation

public struct DinkyImageCompressionResult: Sendable {
    public let outputURL: URL
    public let originalSize: Int64
    public let outputSize: Int64
    public var originalRecoveryURL: URL? = nil
    public let detectedContentType: ContentType?
    public var usedFirstFrameOnly: Bool = false

    public init(
        outputURL: URL,
        originalSize: Int64,
        outputSize: Int64,
        originalRecoveryURL: URL? = nil,
        detectedContentType: ContentType? = nil,
        usedFirstFrameOnly: Bool = false
    ) {
        self.outputURL = outputURL
        self.originalSize = originalSize
        self.outputSize = outputSize
        self.originalRecoveryURL = originalRecoveryURL
        self.detectedContentType = detectedContentType
        self.usedFirstFrameOnly = usedFirstFrameOnly
    }
}
