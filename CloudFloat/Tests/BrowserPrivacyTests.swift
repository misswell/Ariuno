import XCTest
import WebKit
@testable import Ariuno

@MainActor
final class BrowserPrivacyTests: XCTestCase {
    func testPrivateTabsShareTemporaryDataStoreAndNormalTabsUsePersistent() {
        let manager = BrowserTabManager()
        let normal = manager.createTab()
        let privateA = manager.createTab(isPrivate: true)
        let privateB = manager.createTab(isPrivate: true)

        XCTAssertTrue(normal.webView.configuration.websiteDataStore.isPersistent)
        XCTAssertFalse(privateA.webView.configuration.websiteDataStore.isPersistent)
        XCTAssertFalse(privateB.webView.configuration.websiteDataStore.isPersistent)
        XCTAssertTrue(
            privateA.webView.configuration.websiteDataStore
                === privateB.webView.configuration.websiteDataStore
        )
        XCTAssertFalse(
            normal.webView.configuration.websiteDataStore
                === privateA.webView.configuration.websiteDataStore
        )

        for session in manager.sessions {
            session.tearDown()
        }
    }

    func testClosingPrivateTabsIsNotBlockedByPiP() {
        let suiteName = "CloudFloatTests.PrivateRecentlyClosed.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let recentlyClosed = RecentlyClosedStore(defaults: defaults)
        let manager = BrowserTabManager(recentlyClosed: recentlyClosed)
        let privateTab = manager.createTab(isPrivate: true)
        let outcome = manager.closeTab(privateTab)
        XCTAssertEqual(outcome, .closed)
        XCTAssertTrue(recentlyClosed.snapshots.isEmpty)
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testHistoryStoreDoesNotTrackPiPAndIsIndependentOfBrowser() {
        let store = HistoryStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("history-\(UUID().uuidString).json"))
        XCTAssertTrue(store.entries.isEmpty)
        store.clear()
    }
}
