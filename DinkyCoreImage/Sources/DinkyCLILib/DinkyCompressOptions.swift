import DinkyCoreImage
import Foundation

public struct DinkyCompressOptions: Sendable {
    public var format: String
    public var quality: Int?
    public var maxWidth: Int?
    public var maxFileSizeKB: Int?
    public var stripMetadata: Bool
    public var outputDir: URL?
    public var smartQuality: Bool
    public var contentTypeHint: String
    public var parallelLimit: Int
    public var collisionStyle: CollisionNamingStyle
    public var collisionCustomPattern: String
    public var json: Bool

    public init(
        format: String = "auto",
        quality: Int? = nil,
        maxWidth: Int? = nil,
        maxFileSizeKB: Int? = nil,
        stripMetadata: Bool = true,
        outputDir: URL? = nil,
        smartQuality: Bool = true,
        contentTypeHint: String = "auto",
        parallelLimit: Int = 3,
        collisionStyle: CollisionNamingStyle = .finderDuplicate,
        collisionCustomPattern: String = "",
        json: Bool = false
    ) {
        self.format = format
        self.quality = quality
        self.maxWidth = maxWidth
        self.maxFileSizeKB = maxFileSizeKB
        self.stripMetadata = stripMetadata
        self.outputDir = outputDir
        self.smartQuality = smartQuality
        self.contentTypeHint = contentTypeHint
        self.parallelLimit = parallelLimit
        self.collisionStyle = collisionStyle
        self.collisionCustomPattern = collisionCustomPattern
        self.json = json
    }
}
