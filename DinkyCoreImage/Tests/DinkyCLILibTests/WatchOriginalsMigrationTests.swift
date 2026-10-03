@testable import DinkyCoreShared
import XCTest

/// Updating must not change what happens to watch-folder originals for people who already had a
/// watch folder.
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

    func testNewUserIsLeftUnset() {
        WatchOriginalsMigration.runIfNeeded(defaults)
        XCTAssertNil(defaults.object(forKey: "watchOriginalsAction"), "unset follows the general setting (2.14.1+)")
        XCTAssertTrue(defaults.bool(forKey: WatchOriginalsMigration.doneKey))
    }

    func testChoiceMadeIn2_13_1IsLeftAlone() {
        defaults.set(true, forKey: "folderWatchEnabled")
        defaults.set("trash", forKey: "watchOriginalsAction")
        WatchOriginalsMigration.runIfNeeded(defaults)
        XCTAssertEqual(defaults.string(forKey: "watchOriginalsAction"), "trash")
    }

    /// Someone who sets up their first watch folder after updating gets the default (follow the
    /// general setting), not a late copy of it.
    func testRunsOnlyOnce() {
        WatchOriginalsMigration.runIfNeeded(defaults)
        defaults.set(true, forKey: "folderWatchEnabled")
        WatchOriginalsMigration.runIfNeeded(defaults)
        XCTAssertNil(defaults.object(forKey: "watchOriginalsAction"))
    }

    // MARK: - 2.14.1: unset follows the general setting

    private func runBoth() {
        WatchOriginalsMigration.runIfNeeded(defaults)
        WatchOriginalsMigration.runFollowGeneralMigrationIfNeeded(defaults)
    }

    private var policy: WatchOriginalsPolicy {
        WatchOriginalsPolicy(storedRawValue: defaults.string(forKey: "watchOriginalsAction"))
    }

    func testFreshInstallFollowsGeneral() {
        runBoth()
        XCTAssertEqual(policy, .followGeneral)
        XCTAssertEqual(policy.resolved(general: .keep), .keep)
    }

    /// The value 2.13.2 copied from the general setting becomes "follow", so later changes to the
    /// general setting carry over.
    func testCopiedValueBecomesFollow() {
        defaults.set("backup", forKey: "originalsAction")
        defaults.set("backup", forKey: "watchOriginalsAction")
        defaults.set(true, forKey: WatchOriginalsMigration.doneKey)
        WatchOriginalsMigration.runFollowGeneralMigrationIfNeeded(defaults)
        XCTAssertEqual(policy, .followGeneral)
    }

    func testExplicitDifferentChoiceIsKept() {
        defaults.set("keep", forKey: "originalsAction")
        defaults.set("trash", forKey: "watchOriginalsAction")
        defaults.set(true, forKey: WatchOriginalsMigration.doneKey)
        WatchOriginalsMigration.runFollowGeneralMigrationIfNeeded(defaults)
        XCTAssertEqual(policy, .explicit(.trash))
    }

    /// Updating straight from 2.13.0 or earlier with a watch folder: the old migration copies, the new
    /// one turns the copy into "follow".
    func testUpdateFromBeforeWatchSettingFollowsGeneral() {
        defaults.set(true, forKey: "folderWatchEnabled")
        defaults.set("trash", forKey: "originalsAction")
        runBoth()
        XCTAssertEqual(policy, .followGeneral)
        XCTAssertEqual(policy.resolved(general: .trash), .trash)
    }

    /// 2.13.2+ users who never touched the watch picker had the Trash *default*, which was never
    /// written — they now follow the general setting.
    func testUnwrittenTrashDefaultNowFollows() {
        defaults.set(true, forKey: WatchOriginalsMigration.doneKey)
        defaults.set(true, forKey: "folderWatchEnabled")
        WatchOriginalsMigration.runFollowGeneralMigrationIfNeeded(defaults)
        XCTAssertEqual(policy, .followGeneral)
    }

    func testFollowMigrationRunsOnlyOnce() {
        runBoth()
        defaults.set("keep", forKey: "watchOriginalsAction")
        WatchOriginalsMigration.runFollowGeneralMigrationIfNeeded(defaults)
        XCTAssertEqual(policy, .explicit(.keep), "a choice made after the migration is left alone")
    }

    func testPolicyRawValues() {
        XCTAssertEqual(WatchOriginalsPolicy(storedRawValue: nil), .followGeneral)
        XCTAssertEqual(WatchOriginalsPolicy(storedRawValue: "followOutput"), .followGeneral)
        XCTAssertEqual(WatchOriginalsPolicy(storedRawValue: "garbage"), .followGeneral)
        XCTAssertEqual(WatchOriginalsPolicy(storedRawValue: "backup"), .explicit(.backup))
        XCTAssertEqual(WatchOriginalsPolicy.followGeneral.storedRawValue, "followOutput")
        XCTAssertEqual(WatchOriginalsPolicy.explicit(.trash).storedRawValue, "trash")
        XCTAssertEqual(WatchOriginalsPolicy.explicit(.keep).resolved(general: .trash), .keep)
    }
}
