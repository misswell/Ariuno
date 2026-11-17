import XCTest
@testable import Ariuno

@MainActor
final class TabSessionStoreTests: XCTestCase {
    private var directory: URL!
    private var fileURL: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AriunoTabs-\(UUID().uuidString)", isDirectory: true)
        fileURL = directory.appendingPathComponent("tabs-v1.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
        fileURL = nil
        super.tearDown()
    }

    func testSavesAndLoadsRoundTrip() {
        let store = TabSessionStore(fileURL: fileURL, debounce: 0)
        let tabID = UUID()
        store.scheduleSave(
            PersistedBrowserState(
                version: PersistedBrowserState.currentVersion,
                tabs: [
                    PersistedTab(id: tabID, urlString: "https://example.com/a", title: "A", lastVisitedAt: Date())
                ],
                activeTabID: tabID,
                updatedAt: Date()
            )
        )
        store.flush()

        let loaded = store.load()
        XCTAssertEqual(loaded.version, PersistedBrowserState.currentVersion)
        XCTAssertEqual(loaded.tabs.count, 1)
        XCTAssertEqual(loaded.tabs.first?.urlString, "https://example.com/a")
        XCTAssertEqual(loaded.tabs.first?.title, "A")
        XCTAssertEqual(loaded.activeTabID, tabID)
    }

    func testLoadReturnsEmptyWhenFileMissingOrVersionMismatch() throws {
        let store = TabSessionStore(fileURL: fileURL)
        XCTAssertTrue(store.load().tabs.isEmpty)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stale = """
        {"version": 99, "tabs": [{"id": "\(UUID().uuidString)", "urlString": "https://example.com", "title": "x", "lastVisitedAt": "2026-01-01T00:00:00Z"}], "updatedAt": "2026-01-01T00:00:00Z"}
        """
        try Data(stale.utf8).write(to: fileURL)
        XCTAssertTrue(store.load().tabs.isEmpty, "未知版本必须丢弃而不是猜测结构")
    }

    func testBlankAndDuplicateTabsAreDropped() {
        let store = TabSessionStore(fileURL: fileURL)
        let id = UUID()
        store.scheduleSave(
            PersistedBrowserState(
                version: PersistedBrowserState.currentVersion,
                tabs: [
                    PersistedTab(id: id, urlString: "https://example.com", title: "ok", lastVisitedAt: Date()),
                    PersistedTab(id: id, urlString: "https://example.com", title: "dup", lastVisitedAt: Date()),
                    PersistedTab(id: UUID(), urlString: "about:blank", title: "blank", lastVisitedAt: Date()),
                    PersistedTab(id: UUID(), urlString: "   ", title: "empty", lastVisitedAt: Date())
                ],
                activeTabID: id,
                updatedAt: Date()
            )
        )
        store.flush()
        XCTAssertEqual(store.load().tabs.count, 1)
    }

    func testTabListIsCapped() {
        let store = TabSessionStore(fileURL: fileURL, maxTabs: 3)
        let tabs = (0..<10).map { index in
            PersistedTab(
                id: UUID(),
                urlString: "https://example.com/\(index)",
                title: "tab \(index)",
                lastVisitedAt: Date()
            )
        }
        store.scheduleSave(
            PersistedBrowserState(
                version: PersistedBrowserState.currentVersion,
                tabs: tabs,
                activeTabID: tabs[9].id,
                updatedAt: Date()
            )
        )
        store.flush()
        let loaded = store.load()
        XCTAssertEqual(loaded.tabs.count, 3)
        XCTAssertNil(loaded.activeTabID, "活动标签不在保留集合内时必须丢弃")
    }

    func testClearRemovesFile() {
        let store = TabSessionStore(fileURL: fileURL)
        store.scheduleSave(
            PersistedBrowserState(
                version: PersistedBrowserState.currentVersion,
                tabs: [PersistedTab(id: UUID(), urlString: "https://example.com", title: "a", lastVisitedAt: Date())],
                activeTabID: nil,
                updatedAt: Date()
            )
        )
        store.flush()
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        store.clear()
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertTrue(store.load().tabs.isEmpty)
    }
}
