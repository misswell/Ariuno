import SwiftUI
import UIKit
import XCTest
@testable import Ariuno

@MainActor
final class TabThumbnailCacheTests: XCTestCase {
    private var directory: URL!
    private var cache: TabThumbnailCache!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AriunoThumbs-\(UUID().uuidString)", isDirectory: true)
        cache = TabThumbnailCache(directory: directory, maxAge: 60)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        cache = nil
        directory = nil
        super.tearDown()
    }

    func testPersistsPngUnderProvidedCachesDirectory() {
        let tabID = UUID()
        let image = Self.makeImage()
        cache.persist(image, tabID: tabID)

        let fileURL = cache.fileURL(for: tabID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertEqual(fileURL.pathExtension, "png")
        XCTAssertEqual(fileURL.deletingLastPathComponent(), directory)
        XCTAssertNotNil(cache.cachedImage(for: tabID))
    }

    func testExpiredThumbnailIsNotReturned() {
        let tabID = UUID()
        cache.persist(Self.makeImage(), tabID: tabID)
        let future = Date().addingTimeInterval(120)
        XCTAssertNil(cache.cachedImage(for: tabID, now: future))
    }

    func testRemoveAndClearDeleteFiles() {
        let first = UUID()
        let second = UUID()
        cache.persist(Self.makeImage(), tabID: first)
        cache.persist(Self.makeImage(), tabID: second)

        cache.remove(tabID: first)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.fileURL(for: first).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: cache.fileURL(for: second).path))

        cache.clear()
        XCTAssertNil(cache.cachedImage(for: second))
    }

    func testThumbnailsAreNotStoredInUserDefaults() {
        let tabID = UUID()
        cache.persist(Self.makeImage(), tabID: tabID)
        let defaults = UserDefaults.standard
        let leaked = defaults.dictionaryRepresentation().keys.contains {
            $0.lowercased().contains(tabID.uuidString.lowercased())
        }
        XCTAssertFalse(leaked, "缩略图不得写入 UserDefaults")
    }

    private static func makeImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4))
        return renderer.image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
    }
}

@MainActor
final class BrowserContainerTests: XCTestCase {
    private var manager: BrowserTabManager!
    private var window: UIWindow!
    private var hostingController: UIHostingController<BrowserTabHostView>!

    override func setUp() {
        super.setUp()
        manager = BrowserTabManager()
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    }

    override func tearDown() {
        hostingController = nil
        window.isHidden = true
        window = nil
        manager.shutdown()
        manager = nil
        super.tearDown()
    }

    func testSwitchingActiveTabKeepsSameWebViewInstancesAndDoesNotReload() {
        let first = manager.activeSession
        let second = manager.createTab(activate: false)
        let firstWebView = ObjectIdentifier(first.webView)
        let secondWebView = ObjectIdentifier(second.webView)

        mount(active: first)
        XCTAssertNotNil(first.webView.superview)
        XCTAssertNotNil(second.webView.superview, "后台标签保持挂载以保留页面状态")

        mount(active: second)

        XCTAssertEqual(ObjectIdentifier(first.webView), firstWebView)
        XCTAssertEqual(ObjectIdentifier(second.webView), secondWebView)
        XCTAssertEqual(manager.activeSession.id, second.id)
        XCTAssertEqual(first.loadGeneration, 0, "切换标签不得触发加载")
        XCTAssertEqual(second.loadGeneration, 0)
        XCTAssertFalse(first.webView.isLoading)
        XCTAssertFalse(second.webView.isLoading)
        XCTAssertNotNil(first.webView.superview, "旧 WebView 仍由会话持有")
    }

    func testTenTabsKeepDistinctStableWebViewsAcrossSwitches() {
        var sessions = [manager.activeSession]
        for _ in 0..<9 {
            sessions.append(manager.createTab(activate: false))
        }
        let identifiers = sessions.map { ObjectIdentifier($0.webView) }
        XCTAssertEqual(Set(identifiers).count, 10)

        mount(active: sessions[3])
        mount(active: sessions[7])
        mount(active: sessions[0])

        XCTAssertEqual(sessions.map { ObjectIdentifier($0.webView) }, identifiers)
        XCTAssertTrue(sessions.allSatisfy { $0.loadGeneration == 0 })
    }

    private func mount(active: BrowserSession) {
        manager.activateTab(active)
        let view = BrowserTabHostView(
            sessions: manager.sessions,
            activeSessionID: manager.activeSessionID
        )
        if let hostingController {
            hostingController.rootView = view
        } else {
            hostingController = UIHostingController(rootView: view)
            window.rootViewController = hostingController
            window.makeKeyAndVisible()
        }
        hostingController.view.setNeedsLayout()
        hostingController.view.layoutIfNeeded()
    }
}
