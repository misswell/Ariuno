import XCTest
@testable import Ariuno

@MainActor
final class RecentlyClosedStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "CloudFloatTests.RecentlyClosed.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        if let suiteName {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testRecordsSkipsBlankAndCaps() {
        let store = RecentlyClosedStore(defaults: defaults)
        store.record(title: "blank", url: URL(string: "about:blank")!, closedAt: Date())
        XCTAssertTrue(store.snapshots.isEmpty)
        for index in 0..<25 {
            store.record(title: "tab \(index)", url: URL(string: "https://example.com/\(index)")!, closedAt: Date())
        }
        XCTAssertEqual(store.snapshots.count, 20)
        XCTAssertEqual(store.snapshots.first?.urlString, "https://example.com/24")
    }

    func testRestoreLastRemovesSnapshot() {
        let store = RecentlyClosedStore(defaults: defaults)
        store.record(title: "tab", url: URL(string: "https://example.com")!, closedAt: Date())
        let snapshot = store.restoreLast()
        XCTAssertEqual(snapshot?.urlString, "https://example.com")
        XCTAssertTrue(store.snapshots.isEmpty)
    }

    func testClearRemovesAll() {
        let store = RecentlyClosedStore(defaults: defaults)
        store.record(title: "tab", url: URL(string: "https://example.com")!, closedAt: Date())
        store.clear()
        XCTAssertTrue(store.snapshots.isEmpty)
    }
}
