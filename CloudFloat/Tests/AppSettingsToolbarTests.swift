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

    func testFloatingBallDefaultsAndPersistence() {
        let settings = AppSettings(defaults: defaults)
        XCTAssertFalse(settings.collapseToolbarToBallOnOpen)
        XCTAssertEqual(settings.floatingBallX, 0.90, accuracy: 0.001)
        XCTAssertEqual(settings.floatingBallY, 0.62, accuracy: 0.001)

        settings.collapseToolbarToBallOnOpen = true
        settings.floatingBallX = 0.42
        settings.floatingBallY = 0.33

        let reloaded = AppSettings(defaults: defaults)
        XCTAssertTrue(reloaded.collapseToolbarToBallOnOpen)
        XCTAssertEqual(reloaded.floatingBallX, 0.42, accuracy: 0.001)
        XCTAssertEqual(reloaded.floatingBallY, 0.33, accuracy: 0.001)
    }

    func testFullscreenInsetsDefaultPersistAndClamp() {
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.fullscreenInsetTop, 0, accuracy: 0.001)
        XCTAssertEqual(settings.fullscreenInsetBottom, 0, accuracy: 0.001)
        XCTAssertEqual(settings.fullscreenInsetLeft, 0, accuracy: 0.001)
        XCTAssertEqual(settings.fullscreenInsetRight, 0, accuracy: 0.001)

        settings.fullscreenInsetTop = 40
        settings.fullscreenInsetBottom = 24
        settings.fullscreenInsetLeft = 12
        settings.fullscreenInsetRight = 80
        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.fullscreenInsetTop, 40, accuracy: 0.001)
        XCTAssertEqual(reloaded.fullscreenInsetBottom, 24, accuracy: 0.001)
        XCTAssertEqual(reloaded.fullscreenInsetLeft, 12, accuracy: 0.001)
        XCTAssertEqual(reloaded.fullscreenInsetRight, 80, accuracy: 0.001)
    }

    func testFullscreenInsetsAreClampedOnLoad() {
        defaults.set(200.0, forKey: "cf.settings.fullscreenInsetTop")
        defaults.set(-20.0, forKey: "cf.settings.fullscreenInsetLeft")
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.fullscreenInsetTop, 80, accuracy: 0.001)
        XCTAssertEqual(settings.fullscreenInsetLeft, 0, accuracy: 0.001)
    }

    func testToolbarPiPButtonSettingDefaultsAndPersists() {
        let settings = AppSettings(defaults: defaults)
        XCTAssertTrue(settings.showToolbarPiPButton)

        settings.showToolbarPiPButton = false
        let reloaded = AppSettings(defaults: defaults)
        XCTAssertFalse(reloaded.showToolbarPiPButton)
    }

    func testFloatingBallDiameterDefaultsPersistsAndClamps() {
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.floatingBallDiameter, 56, accuracy: 0.001)

        settings.floatingBallDiameter = 72
        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.floatingBallDiameter, 72, accuracy: 0.001)

        defaults.set(200.0, forKey: "cf.settings.floatingBallDiameter")
        let clamped = AppSettings(defaults: defaults)
        XCTAssertEqual(clamped.floatingBallDiameter, 80, accuracy: 0.001)
    }

    func testFloatingBallPositionIsClampedOnLoad() {
        defaults.set(9.0, forKey: "cf.settings.floatingBallX")
        defaults.set(-3.0, forKey: "cf.settings.floatingBallY")
        let settings = AppSettings(defaults: defaults)
        XCTAssertLessThanOrEqual(settings.floatingBallX, 0.95)
        XCTAssertGreaterThanOrEqual(settings.floatingBallY, 0.08)
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
