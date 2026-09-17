import Foundation

/// JSON contract version for agent/terminal consumers (see `docs/local-cli.md` and site `llms.txt`).
public let dinkyImageCompressResultSchema = "dinky.image.compress/1.1.0"
public let dinkyImageServeInfoSchema = "dinky.image.serve/1.0.0"
public let dinkyVideoCompressResultSchema = "dinky.video.compress/1.0.0"
public let dinkyPdfCompressResultSchema = "dinky.pdf.compress/1.0.0"

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
    public var appliedChromaSubsampling: String?
    public var appliedWebpLossless: Bool?
    public var appliedPngOutputMode: String?
    public var error: String?

    public init(
        input: String,
        output: String?,
        originalBytes: Int64,
        outputBytes: Int64?,
        savingsPercent: Double?,
        detectedContent: String?,
        appliedChromaSubsampling: String? = nil,
        appliedWebpLossless: Bool? = nil,
        appliedPngOutputMode: String? = nil,
        error: String?
    ) {
        self.input = input
        self.output = output
        self.originalBytes = originalBytes
        self.outputBytes = outputBytes
        self.savingsPercent = savingsPercent
        self.detectedContent = detectedContent
        self.appliedChromaSubsampling = appliedChromaSubsampling
        self.appliedWebpLossless = appliedWebpLossless
        self.appliedPngOutputMode = appliedPngOutputMode
        self.error = error
    }
}

public struct DinkyVideoCompressResponse: Codable, Sendable {
    public var schema: String
    public var success: Bool
    public var results: [DinkyVideoCompressFileResult]

    public init(schema: String, success: Bool, results: [DinkyVideoCompressFileResult]) {
        self.schema = schema
        self.success = success
        self.results = results
    }
}

public struct DinkyVideoCompressFileResult: Codable, Sendable, Equatable {
    public var input: String
    public var output: String?
    public var originalBytes: Int64
    public var outputBytes: Int64?
    public var savingsPercent: Double?
    public var durationSeconds: Double?
    public var effectiveCodec: String?
    public var isHDR: Bool?
    public var videoContentType: String?
    public var error: String?

    public init(
        input: String,
        output: String?,
        originalBytes: Int64,
        outputBytes: Int64?,
        savingsPercent: Double?,
        durationSeconds: Double?,
        effectiveCodec: String?,
        isHDR: Bool?,
        videoContentType: String?,
        error: String?
    ) {
        self.input = input
        self.output = output
        self.originalBytes = originalBytes
        self.outputBytes = outputBytes
        self.savingsPercent = savingsPercent
        self.durationSeconds = durationSeconds
        self.effectiveCodec = effectiveCodec
        self.isHDR = isHDR
        self.videoContentType = videoContentType
        self.error = error
    }
}

public struct DinkyPdfCompressResponse: Codable, Sendable {
    public var schema: String
    public var success: Bool
    public var results: [DinkyPdfCompressFileResult]

    public init(schema: String, success: Bool, results: [DinkyPdfCompressFileResult]) {
        self.schema = schema
        self.success = success
        self.results = results
    }
}

public struct DinkyPdfCompressFileResult: Codable, Sendable, Equatable {
    public var input: String
    public var output: String?
    public var originalBytes: Int64
    public var outputBytes: Int64?
    public var savingsPercent: Double?
    /// `preserve` or `flatten`
    public var mode: String
    public var qpdfStepUsed: String?
    public var appliedDownsampling: Bool?
    public var error: String?

    public init(
        input: String,
        output: String?,
        originalBytes: Int64,
        outputBytes: Int64?,
        savingsPercent: Double?,
        mode: String,
        qpdfStepUsed: String?,
        appliedDownsampling: Bool?,
        error: String?
    ) {
        self.input = input
        self.output = output
        self.originalBytes = originalBytes
        self.outputBytes = outputBytes
        self.savingsPercent = savingsPercent
        self.mode = mode
        self.qpdfStepUsed = qpdfStepUsed
        self.appliedDownsampling = appliedDownsampling
        self.error = error
    }
}
