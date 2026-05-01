import DinkyCLILib
import Foundation
import XCTest

final class JSONContractTests: XCTestCase {
    func testSchemaVersionMatchesHelpDocumentation() {
        XCTAssertEqual(dinkyImageCompressResultSchema, "dinky.image.compress/1.0.0")
        XCTAssertEqual(dinkyImageServeInfoSchema, "dinky.image.serve/1.0.0")
        XCTAssertEqual(dinkyVideoCompressResultSchema, "dinky.video.compress/1.0.0")
        XCTAssertEqual(dinkyPdfCompressResultSchema, "dinky.pdf.compress/1.0.0")
        XCTAssertEqual(DinkyMakeFixturesCommand.manifestSchema, "dinky.fixtures.manifest/1.0.0")
    }

    func testRoundTripEncode() throws {
        let response = DinkyImageCompressResponse(
            schema: dinkyImageCompressResultSchema,
            success: true,
            results: [
                DinkyImageCompressFileResult(
                    input: "/tmp/a.png",
                    output: "/tmp/a.webp",
                    originalBytes: 1000,
                    outputBytes: 400,
                    savingsPercent: 60,
                    detectedContent: "photo",
                    error: nil
                ),
            ]
        )
        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(DinkyImageCompressResponse.self, from: data)
        XCTAssertEqual(decoded.schema, dinkyImageCompressResultSchema)
        XCTAssertTrue(decoded.success)
        XCTAssertEqual(decoded.results.count, 1)
        XCTAssertEqual(decoded.results[0].input, "/tmp/a.png")
        XCTAssertEqual(decoded.results[0].outputBytes, 400)
    }

    func testVideoResponseRoundTrip() throws {
        let response = DinkyVideoCompressResponse(
            schema: dinkyVideoCompressResultSchema,
            success: true,
            results: [
                DinkyVideoCompressFileResult(
                    input: "a.mov",
                    output: "a.mp4",
                    originalBytes: 10_000,
                    outputBytes: 5000,
                    savingsPercent: 50,
                    durationSeconds: 1.2,
                    effectiveCodec: "hevc",
                    isHDR: false,
                    videoContentType: "generic",
                    error: nil
                ),
            ]
        )
        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(DinkyVideoCompressResponse.self, from: data)
        XCTAssertEqual(decoded.schema, dinkyVideoCompressResultSchema)
        XCTAssertEqual(decoded.results[0].effectiveCodec, "hevc")
    }

    func testPdfResponseRoundTrip() throws {
        let response = DinkyPdfCompressResponse(
            schema: dinkyPdfCompressResultSchema,
            success: true,
            results: [
                DinkyPdfCompressFileResult(
                    input: "a.pdf",
                    output: "b.pdf",
                    originalBytes: 2000,
                    outputBytes: 1500,
                    savingsPercent: 25,
                    mode: "flatten",
                    qpdfStepUsed: nil,
                    appliedDownsampling: false,
                    error: nil
                ),
            ]
        )
        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(DinkyPdfCompressResponse.self, from: data)
        XCTAssertEqual(decoded.results[0].mode, "flatten")
    }
}
