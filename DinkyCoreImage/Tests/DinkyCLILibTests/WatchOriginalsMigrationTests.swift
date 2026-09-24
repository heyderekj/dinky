@testable import DinkyCoreShared
import XCTest

/// Updating to 2.13.1 must not change what happens to watch-folder originals for people who already
/// had a watch folder; only people new to watch folders get the Trash default.
final class WatchOriginalsMigrationTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        suiteName = "dinky-watch-originals-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testExistingWatchUserKeepsDefaultKeepBehaviour() {
        defaults.set(true, forKey: "folderWatchEnabled")
        WatchOriginalsMigration.runIfNeeded(defaults)
        XCTAssertEqual(defaults.string(forKey: "watchOriginalsAction"), "keep")
    }

    func testExistingWatchUserInheritsTheirGeneralSetting() {
        defaults.set("/Users/me/Inbox", forKey: "watchedFolderPath")
        defaults.set("backup", forKey: "originalsAction")
        WatchOriginalsMigration.runIfNeeded(defaults)
        XCTAssertEqual(defaults.string(forKey: "watchOriginalsAction"), "backup")
    }

    func testPresetWatchFolderCountsAsExistingUser() throws {
        let preset: [String: Any] = [
            "id": UUID().uuidString, "name": "Web", "format": "webp",
            "createdAt": 0, "watchFolderEnabled": true,
        ]
        defaults.set(try JSONSerialization.data(withJSONObject: [preset]), forKey: "savedPresetsData")
        WatchOriginalsMigration.runIfNeeded(defaults)
        XCTAssertEqual(defaults.string(forKey: "watchOriginalsAction"), "keep")
    }

    func testNewUserKeepsTrashDefault() {
        WatchOriginalsMigration.runIfNeeded(defaults)
        XCTAssertNil(defaults.object(forKey: "watchOriginalsAction"), "unset means the Trash default applies")
        XCTAssertTrue(defaults.bool(forKey: WatchOriginalsMigration.doneKey))
    }

    func testChoiceMadeIn2_13_1IsLeftAlone() {
        defaults.set(true, forKey: "folderWatchEnabled")
        defaults.set("trash", forKey: "watchOriginalsAction")
        WatchOriginalsMigration.runIfNeeded(defaults)
        XCTAssertEqual(defaults.string(forKey: "watchOriginalsAction"), "trash")
    }

    /// Someone who sets up their first watch folder after updating gets the new default,
    /// not a late copy of the general setting.
    func testRunsOnlyOnce() {
        WatchOriginalsMigration.runIfNeeded(defaults)
        defaults.set(true, forKey: "folderWatchEnabled")
        WatchOriginalsMigration.runIfNeeded(defaults)
        XCTAssertNil(defaults.object(forKey: "watchOriginalsAction"))
    }
}
