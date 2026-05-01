import DinkyCLILib
import Foundation
import XCTest

final class JSONContractTests: XCTestCase {
    func testSchemaVersionMatchesHelpDocumentation() {
        XCTAssertEqual(dinkyImageCompressResultSchema, "dinky.image.compress/1.0.0")
        XCTAssertEqual(dinkyImageServeInfoSchema, "dinky.image.serve/1.0.0")
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
}
