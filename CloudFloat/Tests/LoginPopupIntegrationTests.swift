import UIKit
import WebKit
import XCTest
@testable import CloudFloat

@MainActor
final class LoginPopupIntegrationTests: XCTestCase {
    private var session: BrowserSession?
    private var server: LocalHTTPServer?
    private var window: UIWindow?

    override func tearDown() {
        session?.closePopup()
        session?.tearDown()
        window?.isHidden = true
        window?.rootViewController = nil
        server?.stop()
        session = nil
        server = nil
        window = nil
        super.tearDown()
    }

    func testLoginPopupSampleOpensAndClosingDoesNotReloadMainPage() async throws {
        guard let directory = LocalHTTPServer.testPagesDirectory() else {
            throw PopupTestError.missingTestPages
        }
        let server = LocalHTTPServer(rootDirectory: directory)
        let port = try await server.start()
        self.server = server

        var policy = NavigationPolicy()
        policy.allowsLocalTestPages = true
        policy.localTestPorts = [Int(port)]
        let session = BrowserSession(
            navigationPolicy: policy,
            inPageControlEnabled: false,
            javaScriptCanOpenWindowsAutomatically: true
        )
        self.session = session

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
        root.view.addSubview(session.webView)
        session.webView.frame = root.view.bounds
        self.window = window

        let popupOpened = expectation(description: "popup opened")
        let mainLoaded = expectation(description: "main page loaded")
        popupOpened.assertForOverFulfill = false
        mainLoaded.assertForOverFulfill = false
        session.onEvent = { event in
            switch event {
            case .loadFinished:
                mainLoaded.fulfill()
            case .popupOpened:
                popupOpened.fulfill()
            default:
                break
            }
        }

        let mainWebViewIdentifier = ObjectIdentifier(session.webView)
        let url = try XCTUnwrap(
            URL(string: "http://127.0.0.1:\(port)/login-popup.html?auto=1")
        )
        session.webView.load(URLRequest(url: url))
        await fulfillment(of: [mainLoaded, popupOpened], timeout: 25)

        XCTAssertNotNil(session.activePopup)
        XCTAssertEqual(ObjectIdentifier(session.webView), mainWebViewIdentifier)
        XCTAssertTrue(session.hasLoadedPage)

        try await waitUntil(timeout: 10) {
            session.activePopup?.webView.url?.path == "/popup-target.html"
        }
        XCTAssertEqual(session.activePopup?.webView.url?.host, "127.0.0.1")

        session.closePopup()
        XCTAssertNil(session.activePopup)
        XCTAssertEqual(ObjectIdentifier(session.webView), mainWebViewIdentifier)
        XCTAssertTrue(session.hasLoadedPage)
    }

    private func waitUntil(
        timeout: TimeInterval,
        interval: TimeInterval = 0.2,
        _ condition: @escaping () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() >= deadline {
                XCTFail("Timed out waiting for popup navigation")
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
