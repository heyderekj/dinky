import Foundation

/// JSON contract version for agent/terminal consumers (see `docs/local-cli.md` and site `llms.txt`).
public let dinkyImageCompressResultSchema = "dinky.image.compress/1.0.0"
public let dinkyImageServeInfoSchema = "dinky.image.serve/1.0.0"

public struct DinkyImageCompressResponse: Codable, Sendable {
    public var schema: String
    public var success: Bool
    public var results: [DinkyImageCompressFileResult]

    public init(schema: String, success: Bool, results: [DinkyImageCompressFileResult]) {
        self.schema = schema
        self.success = success
        self.results = results
    }
}

public struct DinkyImageCompressFileResult: Codable, Sendable, Equatable {
    public var input: String
    public var output: String?
    public var originalBytes: Int64
    public var outputBytes: Int64?
    public var savingsPercent: Double?
    public var detectedContent: String?
    public var error: String?

    public init(
        input: String,
        output: String?,
        originalBytes: Int64,
        outputBytes: Int64?,
        savingsPercent: Double?,
        detectedContent: String?,
        error: String?
    ) {
        self.input = input
        self.output = output
        self.originalBytes = originalBytes
        self.outputBytes = outputBytes
        self.savingsPercent = savingsPercent
        self.detectedContent = detectedContent
        self.error = error
    }
}
