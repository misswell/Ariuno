import XCTest
@testable import CloudFloat

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
}
