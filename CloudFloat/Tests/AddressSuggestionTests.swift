import XCTest
@testable import Ariuno

@MainActor
final class AddressSuggestionTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var history: HistoryStore!

    override func setUp() {
        super.setUp()
        suiteName = "CloudFloatTests.AddressSuggestions.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        history = HistoryStore(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("suggestions-\(UUID().uuidString).json")
        )
    }

    override func tearDown() {
        if let suiteName {
            defaults.removePersistentDomain(forName: suiteName)
        }
        history = nil
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testEmptyQueryReturnsNoSuggestions() {
        history.record(title: "Example Domain", url: URL(string: "https://example.com")!)
        XCTAssertTrue(
            AddressSuggestionProvider.suggestions(
                query: "   ",
                history: history.entries,
                bookmarks: []
            ).isEmpty
        )
    }

    func testMatchesHistoryTitleAndURL() {
        history.record(title: "Example Domain", url: URL(string: "https://example.com")!)
        history.record(title: "Wikipedia", url: URL(string: "https://www.wikipedia.org")!)

        let byTitle = AddressSuggestionProvider.suggestions(
            query: "wiki",
            history: history.entries,
            bookmarks: []
        )
        XCTAssertEqual(byTitle.map(\.urlString), ["https://www.wikipedia.org"])

        let byHost = AddressSuggestionProvider.suggestions(
            query: "example.com",
            history: history.entries,
            bookmarks: []
        )
        XCTAssertEqual(byHost.map(\.urlString), ["https://example.com"])
    }

    func testBookmarksComeBeforeHistoryAndDuplicateURLsCollapse() {
        let url = URL(string: "https://example.com/page")!
        history.record(title: "History title", url: url)
        let bookmarks = BookmarkStore(defaults: defaults)
        bookmarks.add(title: "Bookmark title", url: url)

        let results = AddressSuggestionProvider.suggestions(
            query: "example",
            history: history.entries,
            bookmarks: bookmarks.bookmarks
        )
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.kind, .bookmark)
        XCTAssertEqual(results.first?.title, "Bookmark title")
    }

    func testResultLimitIsApplied() {
        for index in 0..<10 {
            history.record(
                title: "Example \(index)",
                url: URL(string: "https://example.com/\(index)")!
            )
        }
        let results = AddressSuggestionProvider.suggestions(
            query: "example",
            history: history.entries,
            bookmarks: [],
            limit: 3
        )
        XCTAssertEqual(results.count, 3)
    }
}
