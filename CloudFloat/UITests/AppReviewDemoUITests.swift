import XCTest

/// App Review evidence flow, run on a physical iPhone. XCUITest records the screen into the
/// result bundle; the recording is attached to App Review. Kept separate from the regular
/// suite so a slow external network cannot make normal CI flaky.
final class AppReviewDemoUITests: XCTestCase {
    func testAppReviewDemoFlow() throws {
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil,
            "App Review demo must run on a physical device"
        )
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()

        // Start from the browser home page even if a previous tab was restored.
        let more = app.buttons["更多操作"]
        if more.waitForExistence(timeout: 8) {
            more.tap()
            if app.buttons["主页"].waitForExistence(timeout: 3) {
                app.buttons["主页"].tap()
            }
        }

        let startField = app.textFields["搜索或输入网址"]
        XCTAssertTrue(startField.waitForExistence(timeout: 15), "start page should be visible")
        sleep(1)
        startField.tap()
        startField.typeText("example.com\n")

        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 25), "first page should load")
        sleep(2)

        // Tabs: open the sheet, create a second tab, navigate it.
        let tabs = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "标签页，共 ")
        ).firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 10))
        tabs.tap()
        XCTAssertTrue(app.buttons["新建标签页"].waitForExistence(timeout: 5))
        sleep(1)
        app.buttons["新建标签页"].tap()

        let secondField = app.textFields["搜索或输入网址"]
        XCTAssertTrue(secondField.waitForExistence(timeout: 10), "new tab should show the start page")
        sleep(1)
        secondField.tap()
        secondField.typeText("www.wikipedia.org\n")
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 25), "second page should load")
        sleep(2)

        // Bookmarks and history sheets.
        if more.waitForExistence(timeout: 5) {
            more.tap()
            if app.buttons["书签"].waitForExistence(timeout: 3) {
                app.buttons["书签"].tap()
                sleep(2)
                if app.buttons["完成"].exists {
                    app.buttons["完成"].tap()
                }
            }
        }
        sleep(1)

        // Fullscreen round-trip.
        if app.buttons["全屏"].waitForExistence(timeout: 5) {
            app.buttons["全屏"].tap()
            sleep(2)
            let ball = app.buttons["展开工具栏"]
            if ball.waitForExistence(timeout: 5) {
                ball.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)).tap()
            }
        }
        sleep(2)

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "app-review-final"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
