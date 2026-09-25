import DinkyCoreShared
import XCTest

final class ActivePresetResolverTests: XCTestCase {

    private func preset(id: UUID, scope: String) throws -> CompressionPreset {
        let json: [String: Any] = [
            "id": id.uuidString, "name": "Web", "format": "webp",
            "createdAt": 0, "presetMediaScopeRaw": scope,
        ]
        return try JSONDecoder().decode(CompressionPreset.self, from: JSONSerialization.data(withJSONObject: json))
    }

    func testActivePresetCoveringTheTypeIsUsed() throws {
        let id = UUID()
        let presets = [try preset(id: id, scope: "image")]
        XCTAssertEqual(ActivePresetResolver.presetID(activePresetID: id.uuidString, savedPresets: presets, mediaType: .image), id)
    }

    func testPresetNotCoveringTheTypeFallsBackToSidebar() throws {
        let id = UUID()
        let presets = [try preset(id: id, scope: "image")]
        XCTAssertNil(ActivePresetResolver.presetID(activePresetID: id.uuidString, savedPresets: presets, mediaType: .video))
    }

    func testNoActivePreset() throws {
        let presets = [try preset(id: UUID(), scope: "all")]
        XCTAssertNil(ActivePresetResolver.presetID(activePresetID: "", savedPresets: presets, mediaType: .image))
        XCTAssertNil(ActivePresetResolver.presetID(activePresetID: "not-a-uuid", savedPresets: presets, mediaType: .image))
    }

    func testDeletedPreset() throws {
        let presets = [try preset(id: UUID(), scope: "all")]
        XCTAssertNil(ActivePresetResolver.presetID(activePresetID: UUID().uuidString, savedPresets: presets, mediaType: .image))
    }

    func testUnknownMediaType() throws {
        let id = UUID()
        let presets = [try preset(id: id, scope: "all")]
        XCTAssertNil(ActivePresetResolver.presetID(activePresetID: id.uuidString, savedPresets: presets, mediaType: nil))
    }
}
