import XCTest

/// Real UI-level checks for the browser chrome. These complement the unit/integration
/// suite: they launch the app and drive actual SwiftUI controls.
final class BrowserUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    func testStartPageExposesBrowserEntryPoints() {
        app.launch()

        XCTAssertTrue(app.staticTexts["Ariuno"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["新建标签页"].exists)
        XCTAssertTrue(app.buttons["书签"].exists)
        XCTAssertTrue(app.buttons["历史"].exists)
        XCTAssertTrue(app.buttons["下载"].exists)
        XCTAssertTrue(app.staticTexts["常用网站"].exists)
        XCTAssertTrue(app.textFields["搜索或输入网址"].exists)
    }

    func testNewTabStaysOnStartPageAndTabSheetCountsIt() {
        app.launch()
        XCTAssertTrue(app.buttons["新建标签页"].waitForExistence(timeout: 15))
        app.buttons["新建标签页"].tap()

        // A fresh tab is a start page, never a hardcoded game page.
        XCTAssertTrue(app.staticTexts["Ariuno"].waitForExistence(timeout: 10))

        let continueButton = app.buttons["继续浏览"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 10))
        continueButton.tap()

        let tabsButton = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "标签页，共 ")
        ).firstMatch
        XCTAssertTrue(tabsButton.waitForExistence(timeout: 15))
        tabsButton.tap()

        let header = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "打开的标签页（")
        ).firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 10))
    }

    func testBookmarksAndHistorySheetsOpenFromStartPage() {
        app.launch()
        XCTAssertTrue(app.buttons["书签"].waitForExistence(timeout: 15))
        app.buttons["书签"].tap()
        XCTAssertTrue(app.navigationBars["书签"].waitForExistence(timeout: 10))
        app.buttons["完成"].tap()

        XCTAssertTrue(app.buttons["历史"].waitForExistence(timeout: 10))
        app.buttons["历史"].tap()
        XCTAssertTrue(app.navigationBars["历史记录"].waitForExistence(timeout: 10))
    }

    func testAddressBarNavigatesToTypedHost() {
        app.launch()
        let field = app.textFields["搜索或输入网址"]
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        field.tap()
        field.typeText("example.com\n")

        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 20))
        let tabsButton = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "标签页，共 ")
        ).firstMatch
        XCTAssertTrue(tabsButton.waitForExistence(timeout: 15))
    }
}
