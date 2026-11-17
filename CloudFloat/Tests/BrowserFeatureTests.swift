import XCTest
@testable import Ariuno

@MainActor
final class BrowserFeatureTests: XCTestCase {
    func testPiPSourceStaysBoundAcrossTabSwitches() {
        let tabs = BrowserTabManager()
        let pip = PiPManager()
        let source = tabs.activeSession

        let coordinator = pip.coordinator(for: source)
        coordinator.handle(event: makePiPEvent(name: .enterpictureinpicture, mode: "picture-in-picture"))

        XCTAssertEqual(pip.activePiPTabID, source.id)
        XCTAssertTrue(pip.isPiPActive(for: source))

        let other = tabs.createTab()
        tabs.activateTab(other)
        XCTAssertEqual(tabs.activeSession.id, other.id)
        XCTAssertEqual(pip.activePiPTabID, source.id)
        XCTAssertTrue(pip.isPiPActive(for: source))
        XCTAssertFalse(pip.isPiPActive(for: other))
        XCTAssertNotEqual(
            ObjectIdentifier(pip.coordinator(for: source)),
            ObjectIdentifier(pip.coordinator(for: other))
        )
    }

    func testClosingPiPSourceRequiresConfirmation() {
        let tabs = BrowserTabManager()
        let pip = PiPManager()
        tabs.pipProtection = { session in pip.isPiPActive(for: session) }
        let source = tabs.activeSession
        pip.coordinator(for: source).handle(event: makePiPEvent(name: .enterpictureinpicture, mode: "picture-in-picture"))

        XCTAssertEqual(tabs.closeTab(source), .requiresPiPConfirmation)
        XCTAssertEqual(tabs.sessions.count, 1)
        XCTAssertEqual(tabs.activeSession.id, source.id)

        XCTAssertEqual(tabs.closeTab(source, force: true), .closed)
        XCTAssertTrue(tabs.sessions.isEmpty || tabs.activeSession.id != source.id)
    }

    func testTenTabsKeepDistinctWebViewsAndStates() {
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

    func testBookmarkFoldersMoveAndSort() {
        let store = BookmarkStore()
        let root = store.rootFolder!
        store.createFolder(named: "工作")
        guard let folder = store.folders.first(where: { $0.name == "工作" }) else {
            XCTFail("folder missing")
            return
        }

        store.add(title: "B", url: URL(string: "https://example.com/b")!, folderID: folder.id)
        store.add(title: "A", url: URL(string: "https://example.com/a")!, folderID: folder.id)
        store.sortBookmarks(in: folder.id, by: .title)
        XCTAssertEqual(store.bookmarks(in: folder.id).map(\.title), ["A", "B"])

        store.move(store.bookmarks(in: folder.id).first!.id, to: root.id)
        XCTAssertEqual(store.bookmarks(in: root.id).count, 1)

        store.removeFolder(folder.id)
        XCTAssertEqual(store.bookmarks(in: root.id).count, 2)
    }

    private func makePiPEvent(
        name: MediaPlaybackEvent.Name,
        mode: String
    ) -> MediaPlaybackEvent {
        let json = """
        {
          "type": "event", "frameId": "frame", "origin": "https://example.com",
          "isTopFrame": true, "name": "\(name.rawValue)", "videoIndex": 0,
          "readyState": 4, "presentationMode": "\(mode)", "isPlaying": true,
          "hasVideo": true, "timestamp": 1700000000000
        }
        """
        let wire = try! JSONDecoder().decode(MediaProbeWireMessage.self, from: Data(json.utf8))
        return MediaPlaybackEvent(wire: wire, receivedAt: Date())!
    }

    func testSearchEnginesBuildQueries() {
        for engine in SearchEngine.allCases {
            let url = engine.searchURL(for: "cloud game")
            XCTAssertNotNil(url)
            XCTAssertTrue(url!.absoluteString.contains("cloud%20game") || url!.absoluteString.contains("cloud+game"))
        }
    }

    func testAllTabsShareOneDownloadQueue() {
        let manager = BrowserTabManager()
        let first = manager.activeSession
        let second = manager.createTab()
        let privateTab = manager.createTab(isPrivate: true)

        XCTAssertTrue(first.downloadManager === second.downloadManager)
        XCTAssertTrue(first.downloadManager === privateTab.downloadManager)
        XCTAssertTrue(manager.downloadManager === first.downloadManager)
        XCTAssertTrue(first.downloadManager.items.isEmpty)

        manager.shutdown()
    }
}
