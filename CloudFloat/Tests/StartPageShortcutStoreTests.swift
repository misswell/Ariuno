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

    func testStartsEmptyOnFirstLaunch() {
        let store = StartPageShortcutStore(defaults: defaults)
        XCTAssertTrue(store.shortcuts.isEmpty)
    }

    func testLegacyStoreIsClearedOnceOnUpgrade() throws {
        let legacy = [
            StartPageShortcut(title: "Old A", systemImage: "globe", urlString: "https://old-a.example"),
            StartPageShortcut(title: "Old B", systemImage: "star", urlString: "https://old-b.example")
        ]
        defaults.set(try JSONEncoder().encode(legacy), forKey: "cf.shortcuts.v1")
        let migrated = StartPageShortcutStore(defaults: defaults)
        XCTAssertTrue(migrated.shortcuts.isEmpty, "pre-schema-2 lists are cleared")

        migrated.add(title: "My Site", urlString: "example.com", systemImage: "star")
        let reloaded = StartPageShortcutStore(defaults: defaults)
        XCTAssertEqual(reloaded.shortcuts.map(\.title), ["My Site"], "post-migration edits persist")
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

        let afterUpdate = StartPageShortcutStore(defaults: defaults)
        XCTAssertEqual(afterUpdate.shortcuts.count, 1)
        XCTAssertEqual(afterUpdate.shortcuts.first?.title, "Example 2")

        store.remove(id: id)
        XCTAssertFalse(store.shortcuts.contains { $0.id == id })

        let reloaded = StartPageShortcutStore(defaults: defaults)
        XCTAssertTrue(reloaded.shortcuts.isEmpty)
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
