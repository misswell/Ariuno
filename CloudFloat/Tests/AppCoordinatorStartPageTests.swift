import XCTest
@testable import Ariuno

@MainActor
final class AppCoordinatorStartPageTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var coordinator: AppCoordinator!

    private var recentlyClosed: RecentlyClosedStore!

    override func setUp() {
        super.setUp()
        suiteName = "CloudFloatTests.StartPage.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        recentlyClosed = RecentlyClosedStore(defaults: defaults)
        coordinator = AppCoordinator(
            settings: AppSettings(defaults: defaults),
            diagnostics: DiagnosticsStore(),
            recentlyClosed: recentlyClosed
        )
    }

    override func tearDown() {
        coordinator.tabs.sessions.forEach { $0.tearDown() }
        coordinator.shutdown()
        defaults.removePersistentDomain(forName: suiteName)
        coordinator = nil
        recentlyClosed = nil
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testRestoreRecentlyClosedTabOpensBrowserOnRestoredSession() {
        coordinator.tabs.recentlyClosed.record(
            title: "示例页面",
            url: URL(string: "https://example.com/page")!,
            closedAt: Date()
        )
        XCTAssertEqual(coordinator.route, .home)
        XCTAssertEqual(coordinator.tabs.sessions.count, 1)

        let restored = coordinator.restoreRecentlyClosedTab()

        XCTAssertEqual(restored?.urlString, "https://example.com/page")
        XCTAssertEqual(coordinator.route, .game)
        XCTAssertTrue(coordinator.hasStartedBrowser)
        XCTAssertEqual(coordinator.tabs.sessions.count, 2)
        XCTAssertEqual(coordinator.browser.id, coordinator.tabs.activeSession.id)
        XCTAssertTrue(coordinator.tabs.recentlyClosed.snapshots.isEmpty)
    }

    func testRestoreRecentlyClosedTabWithoutSnapshotsIsNoOp() {
        let restored = coordinator.restoreRecentlyClosedTab()
        XCTAssertNil(restored)
        XCTAssertEqual(coordinator.route, .home)
        XCTAssertFalse(coordinator.hasStartedBrowser)
        XCTAssertEqual(coordinator.tabs.sessions.count, 1)
    }

    func testCreateTabRoutesToBrowserAndActivatesNewSession() {
        coordinator.createTab()
        XCTAssertEqual(coordinator.route, .game)
        XCTAssertTrue(coordinator.hasStartedBrowser)
        XCTAssertEqual(coordinator.tabs.sessions.count, 2)
        XCTAssertEqual(coordinator.browser.id, coordinator.tabs.sessions.last?.id)
    }

    func testRecentlyClosedStoreExposedThroughCoordinator() {
        XCTAssertTrue(coordinator.tabs.recentlyClosed.snapshots.isEmpty)
        coordinator.tabs.recentlyClosed.record(
            title: "a",
            url: URL(string: "https://example.com/a")!,
            closedAt: Date()
        )
        coordinator.tabs.recentlyClosed.record(
            title: "b",
            url: URL(string: "https://example.com/b")!,
            closedAt: Date()
        )
        XCTAssertEqual(coordinator.tabs.recentlyClosed.snapshots.count, 2)
        XCTAssertEqual(coordinator.tabs.recentlyClosed.snapshots.first?.title, "b")
    }
}
