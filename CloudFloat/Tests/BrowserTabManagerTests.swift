import XCTest
@testable import Ariuno

@MainActor
final class BrowserTabManagerTests: XCTestCase {
    func testStartsWithOneActiveTab() {
        let manager = BrowserTabManager()
        XCTAssertEqual(manager.sessions.count, 1)
        XCTAssertEqual(manager.activeSession.id, manager.activeSessionID)
        XCTAssertTrue(manager.activeSession.isShowingBlankPage)
    }

    func testCreateTabActivatesAndLoadsURL() {
        let manager = BrowserTabManager()
        let first = manager.activeSession
        let url = URL(string: "https://example.com/cloud")!
        let second = manager.createTab(url: url)

        XCTAssertEqual(manager.sessions.count, 2)
        XCTAssertEqual(manager.activeSession.id, second.id)
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(second.webView.url, url)
    }

    func testCloseActiveTabActivatesNeighborAndTearsDownClosedSession() {
        let manager = BrowserTabManager()
        let first = manager.activeSession
        let second = manager.createTab()
        manager.activateTab(first)
        XCTAssertEqual(manager.activeSession.id, first.id)

        manager.closeTab(first)
        XCTAssertEqual(manager.sessions.count, 1)
        XCTAssertEqual(manager.activeSession.id, second.id)
        XCTAssertFalse(manager.sessions.contains(where: { $0.id == first.id }))
    }

    func testClosingLastTabCreatesBlankReplacement() {
        let manager = BrowserTabManager()
        let first = manager.activeSession
        manager.closeTab(first)

        XCTAssertEqual(manager.sessions.count, 1)
        XCTAssertNotEqual(manager.activeSession.id, first.id)
        XCTAssertTrue(manager.activeSession.isShowingBlankPage)
    }

    func testActivateTabUpdatesActiveSession() {
        let manager = BrowserTabManager()
        let first = manager.activeSession
        let second = manager.createTab()
        XCTAssertEqual(manager.activeSession.id, second.id)

        manager.activateTab(first)
        XCTAssertEqual(manager.activeSession.id, first.id)

        manager.activateNextTab()
        XCTAssertEqual(manager.activeSession.id, second.id)

        manager.activatePreviousTab()
        XCTAssertEqual(manager.activeSession.id, first.id)
    }

    func testTenTabsKeepDistinctWebViewsAndPersistStates() {
        let manager = BrowserTabManager()
        var sessions: [BrowserSession] = [manager.activeSession]
        for index in 1..<10 {
            sessions.append(manager.createTab(url: URL(string: "https://example.com/tab\(index)")!))
        }
        XCTAssertEqual(sessions.count, 10)
        XCTAssertEqual(Set(sessions.map(\.id)).count, 10)
        XCTAssertEqual(Set(sessions.map { ObjectIdentifier($0.webView) }).count, 10)
        for session in sessions.dropFirst() {
            session.tearDown()
        }
    }

    func testSessionEventsForwardThroughManager() {
        let manager = BrowserTabManager()
        var observedEvent: BrowserEvent?
        manager.onSessionEvent = { _, event in
            observedEvent = event
        }
        manager.activeSession.handleNavigationStarted()
        XCTAssertEqual(observedEvent, .loadStarted)
    }
}
