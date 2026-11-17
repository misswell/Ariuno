import SwiftUI
import XCTest
@testable import Ariuno

@MainActor
final class MediaSchedulingTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var coordinator: AppCoordinator!

    override func setUp() {
        super.setUp()
        suiteName = "CloudFloatTests.MediaScheduling.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        coordinator = AppCoordinator(
            settings: AppSettings(defaults: defaults),
            diagnostics: DiagnosticsStore(),
            recentlyClosed: RecentlyClosedStore(defaults: defaults)
        )
    }

    override func tearDown() {
        coordinator.tabs.sessions.forEach { $0.tearDown() }
        coordinator.shutdown()
        defaults.removePersistentDomain(forName: suiteName)
        coordinator = nil
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private var firstTab: BrowserSession { coordinator.tabs.sessions[0] }
    private var secondTab: BrowserSession { coordinator.tabs.sessions[1] }

    func testOnlyActiveTabPolls() {
        coordinator.createTab(url: URL(string: "https://example.com/b")!)

        XCTAssertTrue(secondTab.mediaDetector.isPolling)
        XCTAssertFalse(firstTab.mediaDetector.isPolling)
        XCTAssertEqual(coordinator.activelyPollingTabCount, 1)
    }

    func testSwitchingTabsStopsPreviousTabPolling() {
        coordinator.createTab(url: URL(string: "https://example.com/b")!)
        coordinator.activateTab(firstTab)

        XCTAssertTrue(firstTab.mediaDetector.isPolling)
        XCTAssertFalse(secondTab.mediaDetector.isPolling)
        XCTAssertEqual(coordinator.activelyPollingTabCount, 1)
    }

    func testBackgroundStopsAllPollingAndForegroundRestoresOnlyActive() {
        coordinator.createTab(url: URL(string: "https://example.com/b")!)
        XCTAssertEqual(coordinator.activelyPollingTabCount, 1)

        coordinator.handleScenePhase(.background)
        XCTAssertEqual(coordinator.activelyPollingTabCount, 0, "进入后台后不得保留探测定时器")

        coordinator.handleScenePhase(.active)
        XCTAssertEqual(coordinator.activelyPollingTabCount, 1)
        XCTAssertTrue(secondTab.mediaDetector.isPolling)
        XCTAssertFalse(firstTab.mediaDetector.isPolling)
    }

    func testPiPSourceKeepsPollingWhileAnotherTabIsActive() {
        let source = firstTab
        coordinator.pipManager.coordinator(for: source)
            .handle(event: makeEvent(name: .enterpictureinpicture, mode: "picture-in-picture"))
        XCTAssertEqual(coordinator.pipManager.activePiPTabID, source.id)

        coordinator.createTab(url: URL(string: "https://example.com/other")!)

        XCTAssertTrue(secondTab.mediaDetector.isPolling, "活动标签继续探测")
        XCTAssertTrue(source.mediaDetector.isPolling, "PiP 来源保留必要探测")
        XCTAssertEqual(coordinator.activelyPollingTabCount, 2, "最多两个定时器：活动 + PiP 来源")

        coordinator.pipManager.clearActivePiP(for: source)
        coordinator.activateTab(secondTab)
        XCTAssertEqual(coordinator.activelyPollingTabCount, 1)
        XCTAssertFalse(source.mediaDetector.isPolling)
    }

    func testOpeningHomeStopsBrowserPollingButKeepsTabsAlive() {
        coordinator.createTab(url: URL(string: "https://example.com/b")!)
        coordinator.openHome()

        XCTAssertEqual(coordinator.route, .home)
        XCTAssertEqual(coordinator.activelyPollingTabCount, 0)
        XCTAssertEqual(coordinator.tabs.sessions.count, 2)
    }

    func testPiPStateIsGlobalNotTiedToSelectedTab() {
        let source = firstTab
        coordinator.pipManager.coordinator(for: source)
            .handle(event: makeEvent(name: .enterpictureinpicture, mode: "picture-in-picture"))
        coordinator.createTab(url: URL(string: "https://example.com/other")!)

        XCTAssertEqual(coordinator.pipManager.activePiPTabID, source.id)
        XCTAssertTrue(coordinator.isAnyPiPActive)
        XCTAssertFalse(coordinator.session.pipVisible, "活动标签自身并未进入 PiP")
        XCTAssertEqual(coordinator.tabs.activeSessionID, secondTab.id)
    }

    func testEnteringBackgroundDoesNotStopPiPOrDestroySource() {
        let source = firstTab
        coordinator.pipManager.coordinator(for: source)
            .handle(event: makeEvent(name: .enterpictureinpicture, mode: "picture-in-picture"))

        coordinator.handleScenePhase(.background)

        XCTAssertEqual(coordinator.pipManager.activePiPTabID, source.id)
        XCTAssertFalse(source.isClosed)
        XCTAssertTrue(coordinator.tabs.sessions.contains(where: { $0.id == source.id }))
        XCTAssertEqual(coordinator.tabs.sessions.count, 1)
    }

    private func makeEvent(name: MediaPlaybackEvent.Name, mode: String) -> MediaPlaybackEvent {
        let json = """
        {
          "type": "event", "frameId": "frame", "origin": "https://example.com",
          "isTopFrame": true, "name": "\(name.rawValue)", "videoIndex": 0,
          "readyState": 4, "presentationMode": "\(mode)", "isPlaying": true,
          "hasVideo": true, "timestamp": 1700000000000
        }
        """
        let wire = try! JSONDecoder().decode(MediaProbeWireMessage.self, from: Data(json.utf8))
        return MediaPlaybackEvent(wire: wire, receivedAt: Date())!
    }
}
