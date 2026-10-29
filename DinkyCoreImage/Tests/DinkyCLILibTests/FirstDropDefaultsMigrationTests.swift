@testable import DinkyCoreShared
import XCTest

/// New installs get the quieter first-drop defaults; people updating keep what they had.
final class FirstDropDefaultsMigrationTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        suiteName = "dinky-first-drop-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testFreshInstallGetsNewDefaults() {
        FirstDropDefaultsMigration.runIfNeeded(defaults)
        for key in FirstDropDefaultsMigration.changedKeys {
            XCTAssertNil(defaults.object(forKey: key), key)
        }
    }

    func testExistingUserKeepsOldDefaults() {
        defaults.set(true, forKey: "watchOriginalsActionMigrated")
        FirstDropDefaultsMigration.runIfNeeded(defaults)
        for key in FirstDropDefaultsMigration.changedKeys {
            XCTAssertEqual(defaults.object(forKey: key) as? Bool, true, key)
        }
    }

    func testExistingUserChoiceIsLeftAlone() {
        defaults.set(1024.0, forKey: "lifetimeSavedBytesRaw")
        defaults.set(false, forKey: "confirmBeforeEveryCompression")
        FirstDropDefaultsMigration.runIfNeeded(defaults)
        XCTAssertEqual(defaults.object(forKey: "confirmBeforeEveryCompression") as? Bool, false)
        XCTAssertEqual(defaults.object(forKey: "openFolderWhenDone") as? Bool, true)
    }

    func testRunsOnlyOnce() {
        FirstDropDefaultsMigration.runIfNeeded(defaults)
        // Used Dinky after the first run: the migration must not kick in later.
        defaults.set(true, forKey: "watchOriginalsActionMigrated")
        FirstDropDefaultsMigration.runIfNeeded(defaults)
        XCTAssertNil(defaults.object(forKey: "confirmBeforeEveryCompression"))
    }
}
