import XCTest
@testable import Ariuno

@MainActor
final class StartPageShortcutStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "CloudFloatTests.Shortcuts.\(UUID().uuidString)"
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

    func testSeedsBuiltInsOnFirstLaunch() {
        let store = StartPageShortcutStore(defaults: defaults)
        XCTAssertEqual(store.shortcuts.map(\.title), ["Bing", "GitHub", "云星穹铁道"])
    }

    func testAddUpdateAndRemovePersist() {
        let store = StartPageShortcutStore(defaults: defaults)
        let added = store.add(
            title: "Example",
            urlString: "example.com",
            systemImage: "globe"
        )
        XCTAssertNotNil(added)
        XCTAssertEqual(store.shortcuts.last?.urlString, "https://example.com")

        let id = try! XCTUnwrap(added?.id)
        XCTAssertTrue(store.update(id: id, title: "Example 2", urlString: "https://example.com/a", systemImage: "star"))
        XCTAssertEqual(store.shortcuts.last?.title, "Example 2")
        XCTAssertEqual(store.shortcuts.last?.systemImage, "star")

        store.remove(id: id)
        XCTAssertFalse(store.shortcuts.contains { $0.id == id })

        let reloaded = StartPageShortcutStore(defaults: defaults)
        XCTAssertEqual(reloaded.shortcuts.count, 3)
    }

    func testDeletingAllDoesNotReseed() {
        let store = StartPageShortcutStore(defaults: defaults)
        store.remove(at: IndexSet(integersIn: 0..<store.shortcuts.count))
        XCTAssertTrue(store.shortcuts.isEmpty)

        let reloaded = StartPageShortcutStore(defaults: defaults)
        XCTAssertTrue(reloaded.shortcuts.isEmpty, "empty user list must stay empty")
    }

    func testURLCanonicalization() {
        XCTAssertEqual(
            StartPageShortcutStore.normalizedURLString("example.com"),
            "https://example.com"
        )
        XCTAssertEqual(
            StartPageShortcutStore.normalizedURLString("http://example.com/a"),
            "http://example.com/a"
        )
        XCTAssertNil(StartPageShortcutStore.normalizedURLString(""))
        XCTAssertNil(StartPageShortcutStore.normalizedURLString("ftp://example.com"))
    }
}
