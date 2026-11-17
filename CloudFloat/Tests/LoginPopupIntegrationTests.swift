import UIKit
import WebKit
import XCTest
@testable import Ariuno

@MainActor
final class LoginPopupIntegrationTests: XCTestCase {
    private var manager: BrowserTabManager?
    private var server: LocalHTTPServer?
    private var window: UIWindow?

    override func tearDown() {
        manager?.shutdown()
        window?.isHidden = true
        window?.rootViewController = nil
        server?.stop()
        manager = nil
        server = nil
        window = nil
        super.tearDown()
    }

    func testTargetBlankCreatesNewTabAndClosingDoesNotReloadMainPage() async throws {
        guard let directory = LocalHTTPServer.testPagesDirectory() else {
            throw PopupTestError.missingTestPages
        }
        let server = LocalHTTPServer(rootDirectory: directory)
        let port = try await server.start()
        self.server = server

        var policy = NavigationPolicy()
        policy.allowsLocalTestPages = true
        policy.localTestPorts = [Int(port)]
        let manager = BrowserTabManager(
            navigationPolicy: policy,
            inPageControlEnabled: false,
            javaScriptCanOpenWindowsAutomatically: true
        )
        self.manager = manager

        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first else {
            throw PopupTestError.noWindowScene
        }
        let window = UIWindow(windowScene: scene)
        window.frame = UIScreen.main.bounds
        let root = UIViewController()
        root.view.backgroundColor = .black
        window.rootViewController = root
        window.makeKeyAndVisible()
        root.view.addSubview(manager.activeSession.webView)
        manager.activeSession.webView.frame = root.view.bounds
        self.window = window

        let mainLoaded = expectation(description: "main page loaded")
        mainLoaded.assertForOverFulfill = false

        manager.onSessionEvent = { session, event in
            if case .loadFinished = event {
                mainLoaded.fulfill()
            }
        }

        let mainSession = manager.activeSession
        let mainWebViewIdentifier = ObjectIdentifier(mainSession.webView)
        let url = try XCTUnwrap(
            URL(string: "http://127.0.0.1:\(port)/login-popup.html?auto=1")
        )
        manager.activeSession.webView.load(URLRequest(url: url))
        await fulfillment(of: [mainLoaded], timeout: 25)
        try await waitUntil(timeout: 10) {
            manager.sessions.count == 2
        }

        XCTAssertEqual(manager.sessions.count, 2)
        XCTAssertEqual(manager.sessions.first.map { ObjectIdentifier($0.webView) }, mainWebViewIdentifier)
        XCTAssertTrue(mainSession.hasLoadedPage)
        XCTAssertFalse(mainSession.webView.url?.absoluteString.contains("popup-target") == true)

        try await waitUntil(timeout: 10) {
            manager.sessions.last?.webView.url?.path == "/popup-target.html"
        }
        XCTAssertEqual(manager.sessions.last?.webView.url?.host, "127.0.0.1")

        manager.closeTab(manager.sessions.last!)
        XCTAssertEqual(manager.sessions.count, 1)
        XCTAssertEqual(ObjectIdentifier(manager.activeSession.webView), mainWebViewIdentifier)
        XCTAssertTrue(manager.activeSession.hasLoadedPage)
    }

    private func waitUntil(
        timeout: TimeInterval,
        interval: TimeInterval = 0.2,
        _ condition: @escaping () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() >= deadline {
                XCTFail("Timed out waiting for new tab navigation")
                return
            }
            try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
    }
}

private enum PopupTestError: LocalizedError {
    case missingTestPages
    case noWindowScene

    var errorDescription: String? {
        switch self {
        case .missingTestPages: return "TestPages resource missing"
        case .noWindowScene: return "No active UIWindowScene for popup test"
        }
    }
}
