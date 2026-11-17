import SwiftUI
import XCTest
@testable import Ariuno

@MainActor
final class PiPSourceCloseTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var coordinator: AppCoordinator!

    override func setUp() {
        super.setUp()
        suiteName = "CloudFloatTests.PiPClose.\(UUID().uuidString)"
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

    func testClosingPiPSourceWithoutForceRequiresConfirmation() {
        let source = coordinator.tabs.activeSession
        enterPiP(on: source)

        XCTAssertEqual(coordinator.closeTab(source), .requiresPiPConfirmation)
        XCTAssertTrue(coordinator.tabs.sessions.contains(where: { $0.id == source.id }))
        XCTAssertFalse(source.isClosed)
    }

    func testForceCloseStopsPiPBeforeTearingDownWebView() {
        let source = coordinator.tabs.activeSession
        enterPiP(on: source)

        XCTAssertEqual(coordinator.closeTab(source, force: true), .closed)

        // Phase 1: the tab must still exist while the system stops PiP.
        XCTAssertTrue(coordinator.tabs.sessions.contains(where: { $0.id == source.id }))
        XCTAssertFalse(source.isClosed)
        XCTAssertTrue(coordinator.pipManager.pendingCloseTabIDs.contains(source.id))

        // Phase 2: leave event arrives -> tab is torn down.
        coordinator.tabs.onMediaEvent?(source, makeEvent(name: .leavepictureinpicture, mode: "inline"))

        XCTAssertFalse(coordinator.tabs.sessions.contains(where: { $0.id == source.id }))
        XCTAssertTrue(source.isClosed)
        XCTAssertTrue(coordinator.pipManager.pendingCloseTabIDs.isEmpty)
        XCTAssertNil(coordinator.pipManager.activePiPTabID)
        XCTAssertEqual(coordinator.tabs.sessions.count, 1, "浏览器始终保留至少一个标签页")
    }

    func testForceCloseOfInactivePiPSourceKeepsActiveTabSelected() {
        let source = coordinator.tabs.activeSession
        enterPiP(on: source)
        coordinator.createTab(url: URL(string: "https://example.com/other")!)
        let other = coordinator.browser
        coordinator.activateTab(other)
        XCTAssertEqual(coordinator.tabs.activeSessionID, other.id)

        _ = coordinator.closeTab(source, force: true)
        coordinator.tabs.onMediaEvent?(source, makeEvent(name: .leavepictureinpicture, mode: "inline"))

        XCTAssertFalse(coordinator.tabs.sessions.contains(where: { $0.id == source.id }))
        XCTAssertEqual(coordinator.tabs.activeSessionID, other.id)
        XCTAssertFalse(other.isClosed)
    }

    func testBatchCloseDefersProtectedPiPSource() {
        let source = coordinator.tabs.activeSession
        enterPiP(on: source)
        coordinator.createTab(url: URL(string: "https://example.com/other")!)
        let other = coordinator.browser
        let ids = [source.id, other.id]

        XCTAssertEqual(coordinator.closeTabs(withIDs: ids, force: true), .closed)
        XCTAssertTrue(coordinator.tabs.sessions.contains(where: { $0.id == source.id }), "PiP 来源延迟关闭")
        XCTAssertFalse(coordinator.tabs.sessions.contains(where: { $0.id == other.id }), "其余标签立即关闭")

        coordinator.tabs.onMediaEvent?(source, makeEvent(name: .leavepictureinpicture, mode: "inline"))
        XCTAssertFalse(coordinator.tabs.sessions.contains(where: { $0.id == source.id }))
    }

    func testPiPCoordinatorIsReleasedAfterClose() {
        let source = coordinator.tabs.activeSession
        enterPiP(on: source)
        XCTAssertNotNil(coordinator.pipManager.coordinator(for: source.id))

        _ = coordinator.closeTab(source, force: true)
        coordinator.tabs.onMediaEvent?(source, makeEvent(name: .leavepictureinpicture, mode: "inline"))

        XCTAssertNil(coordinator.pipManager.coordinator(for: source.id))
    }

    func testPiPAuditEventsCoverSourceBindingSwitchBackgroundAndClose() {
        let source = coordinator.tabs.activeSession
        coordinator.tabs.onMediaEvent?(
            source,
            makeEvent(name: .enterpictureinpicture, mode: "picture-in-picture")
        )
        XCTAssertEqual(coordinator.pipManager.activePiPTabID, source.id)
        XCTAssertTrue(codes.contains("pip.source_bound"))

        coordinator.createTab(url: URL(string: "https://example.com/audit")!)
        let other = coordinator.browser
        XCTAssertTrue(codes.contains("pip.tab_created_while_active"))

        coordinator.activateTab(source)
        coordinator.activateTab(other)
        XCTAssertTrue(codes.contains("pip.tab_switch_source_retained"))

        coordinator.handleScenePhase(.background)
        XCTAssertTrue(codes.contains("pip.background_retained"))
        coordinator.handleScenePhase(.active)
        XCTAssertTrue(codes.contains("pip.foreground_retained"))

        _ = coordinator.closeTab(source, force: true)
        XCTAssertTrue(codes.contains("pip.close_requested"))

        coordinator.tabs.onMediaEvent?(
            source,
            makeEvent(name: .leavepictureinpicture, mode: "inline")
        )
        XCTAssertTrue(codes.contains("pip.close_completed"))
    }

    private var codes: [String] {
        coordinator.diagnostics.events.map(\.code)
    }

    private func enterPiP(on session: BrowserSession) {
        coordinator.pipManager.coordinator(for: session)
            .handle(event: makeEvent(name: .enterpictureinpicture, mode: "picture-in-picture"))
        XCTAssertEqual(coordinator.pipManager.activePiPTabID, session.id)
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
