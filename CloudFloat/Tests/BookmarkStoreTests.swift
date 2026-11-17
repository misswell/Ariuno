import XCTest
@testable import Ariuno

@MainActor
final class BookmarkStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "CloudFloatTests.BookmarkStore.\(UUID().uuidString)"
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

    func testEmptyByDefaultNoHardcodedSites() {
        let store = BookmarkStore(defaults: defaults)
        XCTAssertTrue(store.bookmarks.isEmpty)
    }

    func testAddPersistsAndReloads() {
        let url = URL(string: "https://example.com/game")!
        let first = BookmarkStore(defaults: defaults)
        first.add(title: "  云游戏  ", url: url)
        XCTAssertEqual(first.bookmarks.count, 1)
        XCTAssertEqual(first.bookmarks.first?.title, "云游戏")
        XCTAssertEqual(first.bookmarks.first?.url, url)

        let second = BookmarkStore(defaults: defaults)
        XCTAssertEqual(second.bookmarks.count, 1)
        XCTAssertEqual(second.bookmarks.first?.urlString, url.absoluteString)
    }

    func testSameURLUpdatesInsteadOfDuplicating() {
        let url = URL(string: "https://example.com/cloud")!
        let store = BookmarkStore(defaults: defaults)
        store.add(title: "旧标题", url: url)
        store.add(title: "新标题", url: url)
        XCTAssertEqual(store.bookmarks.count, 1)
        XCTAssertEqual(store.bookmarks.first?.title, "新标题")
    }

    func testRemoveDeletesBookmark() {
        let store = BookmarkStore(defaults: defaults)
        store.add(title: "示例", url: URL(string: "https://example.com")!)
        guard let bookmark = store.bookmarks.first else {
            XCTFail("bookmark missing")
            return
        }
        store.remove(bookmark.id)
        XCTAssertTrue(store.bookmarks.isEmpty)
    }

    func testIsBookmarkedUsesExactURLString() {
        let store = BookmarkStore(defaults: defaults)
        let url = URL(string: "https://example.com/page")!
        store.add(title: "示例", url: url)
        XCTAssertTrue(store.isBookmarked(url))
        XCTAssertFalse(store.isBookmarked(URL(string: "https://example.com/other")!))
    }

    func testBatchRemoveUsesStableIDsAndPersistsOnce() {
        let store = BookmarkStore(defaults: defaults)
        for index in 0..<4 {
            store.add(
                title: "站点 \(index)",
                url: URL(string: "https://example.com/\(index)")!
            )
        }
        let ids = Set(store.bookmarks.prefix(2).map(\.id))
        store.remove(ids)

        XCTAssertEqual(store.bookmarks.count, 2)
        XCTAssertFalse(store.bookmarks.contains { ids.contains($0.id) })

        let reloaded = BookmarkStore(defaults: defaults)
        XCTAssertEqual(reloaded.bookmarks.count, 2)
        XCTAssertFalse(reloaded.bookmarks.contains { ids.contains($0.id) })
    }

    func testBatchRemoveEmptySetIsNoOp() {
        let store = BookmarkStore(defaults: defaults)
        store.add(title: "保留", url: URL(string: "https://example.com/keep")!)
        store.remove(Set<UUID>())
        XCTAssertEqual(store.bookmarks.count, 1)
    }
}
