import XCTest
@testable import Ariuno

@MainActor
final class HistoryStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var fileURL: URL!

    override func setUp() {
        super.setUp()
        suiteName = "CloudFloatTests.HistoryStore.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AriunoTests-\(UUID().uuidString)")
            .appendingPathComponent("history.json")
    }

    override func tearDown() {
        if let suiteName {
            defaults.removePersistentDomain(forName: suiteName)
        }
        try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
        defaults = nil
        suiteName = nil
        fileURL = nil
        super.tearDown()
    }

    func testRecordsAndPersistsAcrossInstances() async throws {
        let first = HistoryStore(fileURL: fileURL)
        first.record(title: "示例页面", url: URL(string: "https://example.com/page")!)
        XCTAssertFalse(first.entries.isEmpty)

        // Flush synchronously so the test is not racing the async writer.
        first.flush()

        let second = HistoryStore(fileURL: fileURL)
        XCTAssertEqual(second.entries.count, 1)
        XCTAssertEqual(second.entries.first?.title, "示例页面")
    }

    func testSearchesTitleAndURL() {
        let store = HistoryStore(fileURL: fileURL)
        store.record(title: "云游戏", url: URL(string: "https://game.example.com")!)
        store.record(title: "新闻", url: URL(string: "https://news.example.org")!)
        XCTAssertEqual(store.entries(matching: "云").count, 1)
        XCTAssertEqual(store.entries(matching: "news.example").count, 1)
        XCTAssertEqual(store.entries(matching: "不存在").count, 0)
    }

    func testSkipsBlankAndFileEntries() {
        let store = HistoryStore(fileURL: fileURL)
        store.record(title: "blank", url: URL(string: "about:blank")!)
        store.record(title: "local", url: URL(string: "file:///tmp/page.html")!)
        XCTAssertTrue(store.entries.isEmpty)
    }

    func testCapsHistoryAndSupportsDeleteClear() {
        let store = HistoryStore(fileURL: fileURL, limit: 3)
        for index in 0..<5 {
            store.record(title: "page \(index)", url: URL(string: "https://example.com/\(index)")!)
        }
        XCTAssertEqual(store.entries.count, 3)
        XCTAssertEqual(store.entries.first?.urlString, "https://example.com/4")

        guard let id = store.entries.first?.id else {
            XCTFail("entry missing")
            return
        }
        store.remove(id)
        XCTAssertEqual(store.entries.count, 2)
        store.clear()
        XCTAssertTrue(store.entries.isEmpty)
    }
}
