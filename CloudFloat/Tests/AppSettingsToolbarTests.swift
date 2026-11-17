import XCTest
@testable import Ariuno

@MainActor
final class AppSettingsToolbarTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "CloudFloatTests.SettingsToolbar.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testToolbarStaysVisibleByDefaultEvenWithLegacyValue() {
        // Simulate the old default (auto-hide = true) written before this change.
        defaults.set(true, forKey: "cf.settings.autoHideToolbar")
        let settings = AppSettings(defaults: defaults)
        XCTAssertFalse(settings.autoHideToolbar, "未明确选择时工具栏应保持可见")
    }

    func testExplicitAutoHideChoiceIsHonored() {
        defaults.set(true, forKey: "cf.settings.autoHideToolbar.explicit")
        defaults.set(true, forKey: "cf.settings.autoHideToolbar")
        let settings = AppSettings(defaults: defaults)
        XCTAssertTrue(settings.autoHideToolbar)
    }

    func testTogglingMarksChoiceExplicit() {
        let settings = AppSettings(defaults: defaults)
        XCTAssertFalse(settings.autoHideToolbar)
        settings.autoHideToolbar = true
        XCTAssertTrue(defaults.bool(forKey: "cf.settings.autoHideToolbar.explicit"))

        let reloaded = AppSettings(defaults: defaults)
        XCTAssertTrue(reloaded.autoHideToolbar)
    }
}
