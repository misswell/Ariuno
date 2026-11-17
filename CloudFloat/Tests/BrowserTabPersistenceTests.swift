import XCTest
@testable import Ariuno

@MainActor
final class BrowserTabPersistenceTests: XCTestCase {
    private var directory: URL!
    private var fileURL: URL!
    private var managers: [BrowserTabManager] = []

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AriunoTabRestore-\(UUID().uuidString)", isDirectory: true)
        fileURL = directory.appendingPathComponent("tabs-v1.json")
    }

    override func tearDown() {
        managers.forEach { $0.shutdown() }
        managers = []
        try? FileManager.default.removeItem(at: directory)
        directory = nil
        fileURL = nil
        super.tearDown()
    }

    private func makeManager(restore: Bool = true) -> BrowserTabManager {
        let manager = BrowserTabManager(
            persistence: TabSessionStore(fileURL: fileURL, debounce: 0),
            restorePersistedTabs: restore
        )
        managers.append(manager)
        return manager
    }

    func testRestoresTabsAndActiveTabOnColdStart() {
        let first = makeManager(restore: false)
        let a = first.createTab(activate: false)
        let b = first.createTab(activate: false)
        a.applyRestoredMetadata(url: URL(string: "https://example.com/a")!, title: "Page A", lastVisitedAt: Date())
        b.applyRestoredMetadata(url: URL(string: "https://example.com/b")!, title: "Page B", lastVisitedAt: Date())
        first.activateTab(a)
        first.savePersistedStateNow()
        XCTAssertEqual(first.sessions.count, 3, "初始空白标签 + 两个页面")

        let second = makeManager()
        XCTAssertEqual(second.sessions.count, 2)
        XCTAssertEqual(second.activeSessionID, a.id)
        XCTAssertEqual(second.activeSession.displayTitle, "Page A")
        XCTAssertEqual(second.activeSession.displayURL?.absoluteString, "https://example.com/a")
        XCTAssertTrue(second.activeSession.isShowingBlankPage, "冷启动只恢复元数据，不应自动发请求")
    }

    func testRestoredTabLoadsOnlyWhenActivated() {
        let first = makeManager(restore: false)
        let a = first.createTab()
        a.applyRestoredMetadata(url: URL(string: "https://example.com/a")!, title: "A", lastVisitedAt: Date())
        first.savePersistedStateNow()

        let second = makeManager()
        let restored = second.activeSession
        XCTAssertTrue(restored.isShowingBlankPage)
        XCTAssertEqual(restored.loadGeneration, 0)
        XCTAssertTrue(restored.resumeRestoredPageIfNeeded())
        XCTAssertEqual(restored.loadGeneration, 1)
        XCTAssertFalse(restored.resumeRestoredPageIfNeeded(), "同一恢复地址只加载一次")
    }

    func testPrivateTabsAreNeverPersisted() {
        let first = makeManager(restore: false)
        let normal = first.createTab()
        normal.applyRestoredMetadata(url: URL(string: "https://example.com/normal")!, title: "normal", lastVisitedAt: Date())
        let privateTab = first.createTab(isPrivate: true)
        privateTab.applyRestoredMetadata(url: URL(string: "https://example.com/private")!, title: "private", lastVisitedAt: Date())
        XCTAssertTrue(privateTab.isPrivate)
        first.savePersistedStateNow()

        let second = makeManager()
        XCTAssertFalse(second.sessions.contains { $0.displayURL?.absoluteString.contains("/private") == true })
        XCTAssertEqual(second.sessions.count, 1, "普通标签应被保留")
    }

    func testClosingActiveTabPersistsNewActiveSelection() {
        let first = makeManager(restore: false)
        let a = first.createTab()
        a.applyRestoredMetadata(url: URL(string: "https://example.com/a")!, title: "A", lastVisitedAt: Date())
        let b = first.createTab()
        b.applyRestoredMetadata(url: URL(string: "https://example.com/b")!, title: "B", lastVisitedAt: Date())
        first.activateTab(b)
        first.savePersistedStateNow()
        XCTAssertEqual(first.activeSessionID, b.id)

        first.closeTab(b, force: true)
        first.savePersistedStateNow()

        let second = makeManager()
        XCTAssertEqual(second.sessions.count, 1)
        XCTAssertEqual(second.sessions.first?.displayURL?.absoluteString, "https://example.com/a")
        XCTAssertEqual(second.activeSessionID, a.id)
    }

    func testBatchCloseUsesStableIDSnapshot() {
        let manager = makeManager(restore: false)
        var sessions = [manager.activeSession]
        for index in 0..<4 {
            sessions.append(manager.createTab(url: URL(string: "https://example.com/\(index)")!, activate: false))
        }
        let victims = [sessions[1].id, sessions[3].id]

        XCTAssertEqual(manager.closeTabs(withIDs: victims, force: true), .closed)

        XCTAssertEqual(manager.sessions.count, 3)
        XCTAssertTrue(manager.sessions.contains(where: { $0.id == sessions[0].id }))
        XCTAssertTrue(manager.sessions.contains(where: { $0.id == sessions[2].id }))
        XCTAssertTrue(manager.sessions.contains(where: { $0.id == sessions[4].id }))
        XCTAssertFalse(manager.sessions.contains(where: { $0.id == sessions[1].id }))
        XCTAssertFalse(manager.sessions.contains(where: { $0.id == sessions[3].id }))
    }

    func testClosedSessionDropsEventsAndHandlers() {
        let manager = makeManager(restore: false)
        let session = manager.activeSession
        session.tearDown()
        XCTAssertTrue(session.isClosed)
        XCTAssertNil(session.onEvent)
        XCTAssertNil(session.onCreateWindow)
        XCTAssertNil(session.onAnyChange)
        // tearDown is idempotent.
        session.tearDown()
        XCTAssertTrue(session.isClosed)
    }

    func testClosedSessionIsDeallocated() {
        let manager = makeManager(restore: false)
        var session: BrowserSession? = manager.createTab()
        weak var weakSession = session
        XCTAssertNotNil(weakSession)

        manager.closeTab(session!, force: true)
        session = nil
        autoreleasepool {}

        XCTAssertNil(weakSession, "关闭标签后不得被管理器/观察者/消息处理器继续持有")
    }

    func testTabManagerKeepsSingleSourceOfTruthForActiveTab() {
        let manager = makeManager(restore: false)
        let a = manager.activeSession
        let b = manager.createTab(url: URL(string: "https://example.com/b")!)
        XCTAssertEqual(manager.activeSessionID, b.id)
        manager.activateTab(a)
        XCTAssertEqual(manager.activeSessionID, a.id)
        XCTAssertEqual(manager.activeSession.id, a.id)
        manager.closeTab(a, force: true)
        XCTAssertEqual(manager.sessions.count, 1)
        XCTAssertEqual(manager.activeSessionID, b.id)
    }
}
