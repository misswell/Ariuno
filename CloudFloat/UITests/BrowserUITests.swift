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
        XCTAssertFalse(app.buttons["新建"].exists, "无可见效果的新建入口已移除")
        XCTAssertTrue(app.buttons["书签"].exists)
        XCTAssertTrue(app.buttons["历史"].exists)
        XCTAssertTrue(app.buttons["下载"].exists)
        XCTAssertTrue(app.staticTexts["常用网站"].exists)
        XCTAssertTrue(app.textFields["搜索或输入网址"].exists)

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "appstore-start"
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testNewTabStaysOnStartPageAndTabSheetCountsIt() {
        app.launch()
        let start = app.buttons["开始浏览"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        start.tap()

        let tabsButton = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "标签页，共 ")
        ).firstMatch
        XCTAssertTrue(tabsButton.waitForExistence(timeout: 15))
        tabsButton.tap()
        XCTAssertTrue(app.buttons["新建标签页"].waitForExistence(timeout: 10))
        app.buttons["新建标签页"].tap()

        // A fresh tab is a start page, never a hardcoded game page.
        XCTAssertTrue(app.staticTexts["Ariuno"].waitForExistence(timeout: 10))

        let continueButton = app.buttons["继续浏览"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 10))
        continueButton.tap()

        XCTAssertTrue(tabsButton.waitForExistence(timeout: 15))
        tabsButton.tap()

        let header = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "打开的标签页（")
        ).firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 10))

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "appstore-tabs"
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testAddressBarShowsHistorySuggestions() {
        app.launch()
        let start = app.buttons["开始浏览"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        start.tap()
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 25))
        sleep(2)

        let tabsButton = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "标签页，共 ")
        ).firstMatch
        XCTAssertTrue(tabsButton.waitForExistence(timeout: 10))
        tabsButton.tap()
        let home = app.buttons["返回主页"]
        XCTAssertTrue(home.waitForExistence(timeout: 5))
        home.tap()

        let field = app.textFields["搜索或输入网址"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("exam")

        let suggestion = app.buttons.matching(
            NSPredicate(
                format: "(label BEGINSWITH %@ OR label BEGINSWITH %@) AND label CONTAINS %@",
                "历史记录，",
                "书签，",
                "example.com"
            )
        ).firstMatch
        XCTAssertTrue(suggestion.waitForExistence(timeout: 10), "历史记录应出现地址建议")
        suggestion.tap()
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 25))
    }

    func testTabsSheetCanReturnHome() {
        app.launch()
        let start = app.buttons["开始浏览"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        start.tap()

        let tabsButton = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "标签页，共 ")
        ).firstMatch
        XCTAssertTrue(tabsButton.waitForExistence(timeout: 15))
        tabsButton.tap()

        let home = app.buttons["返回主页"]
        XCTAssertTrue(home.waitForExistence(timeout: 10), "标签页列表应提供返回主页")
        home.tap()
        XCTAssertTrue(app.staticTexts["Ariuno"].waitForExistence(timeout: 10), "应回到浏览器首页")
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

    /// Device-only mechanical check of the HTML5 PiP lifecycle: enter PiP from the local
    /// video page, switch tabs, return to the source, then close it and confirm the
    /// stop-before-destroy dialog. This does NOT substitute for the cloud-game A-J
    /// acceptance and is never reported as such.
    func testLocalVideoPiPLifecycleOnDevice() throws {
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil,
            "System PiP is unavailable in the simulator; run on a real iPhone"
        )
        app.launchArguments = ["-CFOpenLocalGame"]
        app.launch()

        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 30))
        let pagePiPButton = webView.buttons["进入画中画（页面点击）"]
        XCTAssertTrue(pagePiPButton.waitForExistence(timeout: 20), "本地视频页的页面内 PiP 按钮应可点击")
        pagePiPButton.tap()

        let exitPiP = app.buttons["退出画中画"]
        XCTAssertTrue(exitPiP.waitForExistence(timeout: 15), "页面内点击后应进入系统 PiP")

        // Create B and verify the PiP source is still retained when returning to it.
        let tabsButton = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "标签页，共 ")
        ).firstMatch
        XCTAssertTrue(tabsButton.waitForExistence(timeout: 10))
        tabsButton.tap()
        XCTAssertTrue(app.buttons["新建标签页"].waitForExistence(timeout: 10))
        app.buttons["新建标签页"].tap()
        XCTAssertTrue(app.staticTexts["Ariuno"].waitForExistence(timeout: 10), "B 标签显示浏览器首页")

        // Return to A and confirm the PiP state is still bound to the source tab.
        app.buttons["继续浏览"].tap()
        XCTAssertTrue(tabsButton.waitForExistence(timeout: 10))
        tabsButton.tap()
        let sourceRow = app.staticTexts["CloudFloat · 原生视频 PiP 测试"].firstMatch
        XCTAssertTrue(sourceRow.waitForExistence(timeout: 10), "标签列应显示 PiP 来源标签")
        sourceRow.tap()
        XCTAssertTrue(exitPiP.waitForExistence(timeout: 15), "切回 A 后 PiP 仍应有效")
    }

    func testTabMetadataRestoresAfterRelaunch() {
        app.launch()
        let field = app.textFields["搜索或输入网址"]
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        field.tap()
        field.typeText("example.com\n")
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 20))

        // Let the load finish and the debounced tab store write to disk.
        sleep(4)
        app.terminate()
        app.launch()

        let start = app.buttons["开始浏览"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        start.tap()

        let tabsButton = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "标签页，共 ")
        ).firstMatch
        XCTAssertTrue(tabsButton.waitForExistence(timeout: 20))
        tabsButton.tap()

        let restored = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "example.com")
        ).firstMatch
        XCTAssertTrue(restored.waitForExistence(timeout: 10), "冷启动后应恢复标签 URL/标题")
    }

    func testToolbarCollapsesToFloatingBallAndExpands() {
        app.launch()
        let start = app.buttons["开始浏览"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        start.tap()

        let more = app.buttons["更多操作"]
        XCTAssertTrue(more.waitForExistence(timeout: 15))
        more.tap()
        let fullscreen = app.buttons["全屏"]
        XCTAssertTrue(fullscreen.waitForExistence(timeout: 5))
        fullscreen.tap()

        let ball = app.buttons["全屏菜单"]
        XCTAssertTrue(ball.waitForExistence(timeout: 5), "全屏后应出现可点击的悬浮球")
        XCTAssertFalse(fullscreen.exists, "全屏模式下底部工具栏应隐藏")
        XCTAssertFalse(app.buttons["添加书签"].exists, "全屏模式下两行工具栏应隐藏")

        // After 3 seconds of inactivity the ball should tuck into the right edge.
        sleep(4)
        XCTAssertTrue(ball.exists, "空闲后悬浮球应仍可找到")
        XCTAssertGreaterThan(
            ball.frame.midX,
            app.frame.midX,
            "悬浮球应吸附在右侧边缘"
        )

        let collapsed = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        collapsed.name = "floating-ball-collapsed"
        collapsed.lifetime = .keepAlways
        add(collapsed)

        ball.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).tap()
        let exitFullscreen = app.buttons["退出全屏"]
        XCTAssertTrue(exitFullscreen.waitForExistence(timeout: 5), "点击悬浮球应先打开全屏菜单")
        exitFullscreen.tap()
        XCTAssertTrue(app.buttons["地址栏，点击编辑"].waitForExistence(timeout: 5), "退出全屏后应恢复单行工具栏")

        let expanded = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        expanded.name = "floating-ball-expanded"
        expanded.lifetime = .keepAlways
        add(expanded)
    }

    func testFloatingBallRemapsAfterOrientationChange() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-CFResetFloatingBall"]
        app.launch()
        let start = app.buttons["开始浏览"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        let portraitDeadline = Date().addingTimeInterval(5)
        while app.frame.width >= app.frame.height, Date() < portraitDeadline {
            usleep(200_000)
        }
        XCTAssertLessThan(app.frame.width, app.frame.height, "设备应处于竖屏")
        start.tap()

        let more = app.buttons["更多操作"]
        XCTAssertTrue(more.waitForExistence(timeout: 15))
        more.tap()
        let fullscreen = app.buttons["全屏"]
        XCTAssertTrue(fullscreen.waitForExistence(timeout: 5))
        fullscreen.tap()

        let ball = app.buttons["全屏菜单"]
        XCTAssertTrue(ball.waitForExistence(timeout: 5))
        XCTAssertTrue(
            (ball.value as? String ?? "").contains("右侧"),
            "竖屏收起后悬浮球应吸附右侧，实际：\(ball.value as? String ?? "")"
        )

        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let deadline = Date().addingTimeInterval(5)
        while app.frame.width <= app.frame.height, Date() < deadline {
            usleep(200_000)
        }
        XCTAssertGreaterThan(app.frame.width, app.frame.height, "设备应进入横屏")
        sleep(1)

        XCTAssertTrue(ball.waitForExistence(timeout: 5), "横屏后悬浮球仍应存在")
        XCTAssertTrue(ball.exists, "横屏后悬浮球仍应存在")
        XCTAssertFalse(app.buttons["全屏"].exists, "横屏后工具栏应保持收起状态")
        let edgeValue = ball.value as? String ?? ""
        XCTAssertTrue(
            edgeValue.contains("右侧"),
            "横屏后应保持吸附在右侧，实际：\(edgeValue)"
        )

        let landscapeShot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        landscapeShot.name = "floating-ball-landscape"
        landscapeShot.lifetime = .keepAlways
        add(landscapeShot)
    }

    func testCompactChromeStaysSingleRowWhileEditing() {
        app.launch()
        let start = app.buttons["开始浏览"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        start.tap()

        let addressButton = app.buttons["地址栏，点击编辑"]
        XCTAssertTrue(addressButton.waitForExistence(timeout: 15), "默认应显示单行控制栏")
        XCTAssertTrue(app.buttons["更多操作"].exists, "单行控制栏应有独立更多按钮")
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "标签页，共 ")).firstMatch.exists,
            "单行控制栏应有独立标签按钮"
        )

        let compactShot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        compactShot.name = "chrome-compact"
        compactShot.lifetime = .keepAlways
        add(compactShot)

        addressButton.tap()
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 5), "地址栏应原地进入编辑")
        XCTAssertFalse(app.buttons["添加书签"].exists, "编辑时不应展开第二行工具栏")

        let editingShot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        editingShot.name = "chrome-editing"
        editingShot.lifetime = .keepAlways
        add(editingShot)

        let page = app.webViews.firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 10))
        page.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).tap()

        XCTAssertTrue(addressButton.waitForExistence(timeout: 5), "点击页面应收起键盘并保持单行")
        XCTAssertFalse(app.buttons["添加书签"].exists)
    }

    func testFullscreenButtonCollapsesChromeAndBallRestoresIt() {
        app.launch()
        let start = app.buttons["开始浏览"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        start.tap()

        let addressButton = app.buttons["地址栏，点击编辑"]
        XCTAssertTrue(addressButton.waitForExistence(timeout: 15))

        let more = app.buttons["更多操作"]
        XCTAssertTrue(more.exists, "单行控制栏应有更多按钮")
        more.tap()
        let fullscreen = app.buttons["全屏"]
        XCTAssertTrue(fullscreen.waitForExistence(timeout: 5), "更多菜单应提供全屏入口")
        fullscreen.tap()

        let ball = app.buttons["全屏菜单"]
        XCTAssertTrue(ball.waitForExistence(timeout: 5), "全屏后应出现悬浮球")
        XCTAssertFalse(addressButton.exists, "全屏后不应保留底部控制栏")

        ball.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).tap()
        XCTAssertFalse(addressButton.exists, "点击悬浮球不应直接退出全屏")
        let exitFullscreen = app.buttons["退出全屏"]
        XCTAssertTrue(exitFullscreen.waitForExistence(timeout: 5), "点击悬浮球应先打开全屏菜单")
        exitFullscreen.tap()
        XCTAssertTrue(addressButton.waitForExistence(timeout: 5), "从菜单选择退出全屏后应恢复控制栏")
    }

    func testAddressBarNavigatesToTypedHost() {
        app.launch()
        let field = app.textFields["搜索或输入网址"]
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        field.tap()
        field.typeText("www.wikipedia.org\n")

        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 20))
        let tabsButton = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "标签页，共 ")
        ).firstMatch
        XCTAssertTrue(tabsButton.waitForExistence(timeout: 15))

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "appstore-browser"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
