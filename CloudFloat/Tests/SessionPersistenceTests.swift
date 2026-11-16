import SwiftUI
import UIKit
import WebKit
import XCTest
@testable import CloudFloat

@MainActor
final class SessionPersistenceTests: XCTestCase {
    private var server: LocalHTTPServer?
    private var window: UIWindow?
    private var coordinator: AppCoordinator?
    private var settingsSuiteName: String?

    override func tearDown() {
        coordinator?.shutdown()
        coordinator = nil
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
        server?.stop()
        server = nil
        if let settingsSuiteName {
            UserDefaults(suiteName: settingsSuiteName)?
                .removePersistentDomain(forName: settingsSuiteName)
        }
        settingsSuiteName = nil
        super.tearDown()
    }

    // T09: WebKit persistent cookie storage survives a BrowserSession/web-view recreation.
    func testCookiesPersistAcrossBrowserSessionInstances() async throws {
        let (server, port) = try await startServer()
        self.server = server
        let directory = LocalHTTPServer.testPagesDirectory()
        let policy = NavigationPolicy(
            allowsLocalTestPages: true,
            localTestPorts: [Int(port)],
            allowedFileDirectory: directory
        )
        let cookieValue = "value-\(UUID().uuidString.prefix(8))"

        let first = BrowserSession(navigationPolicy: policy)
        do {
            try await load(primaryURL("cookie-set.html?value=\(cookieValue)", port: port), in: first)
            let cookie = try await evaluate("document.cookie", in: first.webView) as? String ?? ""
            XCTAssertTrue(cookie.contains("cf_test_cookie=\(cookieValue)"), "cookie was not set: \(cookie)")
        } catch {
            first.tearDown()
            throw error
        }
        first.tearDown()

        // A new BrowserSession has a new WKWebView but the same persistent WKWebsiteDataStore.
        let second = BrowserSession(navigationPolicy: policy)
        defer { second.tearDown() }
        try await load(primaryURL("cookie-read.html", port: port), in: second)
        let persistedCookie = try await evaluate("document.cookie", in: second.webView) as? String ?? ""
        XCTAssertTrue(
            persistedCookie.contains("cf_test_cookie=\(cookieValue)"),
            "cookie did not persist across BrowserSession instances: \(persistedCookie)"
        )

        _ = try? await evaluate(
            "document.cookie='cf_test_cookie=; Max-Age=0; path=/; SameSite=Lax'",
            in: second.webView
        )
    }

    // T11/session retention: re-creating the SwiftUI host must not recreate or reload the
    // WebView, and page-level JS state must survive home/game navigation.
    func testSwiftUIHostRecreationKeepsWebViewAndPageState() async throws {
        let (server, port) = try await startServer()
        self.server = server

        let suiteName = "CloudFloatTests.SessionPersistence.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        settingsSuiteName = suiteName
        let settings = AppSettings(defaults: defaults)
        let coordinator = AppCoordinator(
            settings: settings,
            diagnostics: DiagnosticsStore()
        )
        self.coordinator = coordinator

        let url = primaryURL("native-video.html", port: port)
        coordinator.loadDebugLocalPage(url)
        try await waitUntil(timeout: 25) {
            coordinator.browser.hasLoadedPage && !coordinator.browser.isLoading
        }

        let webViewIdentifier = ObjectIdentifier(coordinator.browser.webView)
        let loadedURL = coordinator.browser.webView.url?.absoluteString
        let marker = "kept-\(UUID().uuidString.prefix(6))"
        _ = try await evaluate(
            "window.__cfSessionMarker = '\(marker)'; 'ok'",
            in: coordinator.browser.webView
        )

        try installRootView(coordinator)
        try await Task.sleep(nanoseconds: 300_000_000)

        coordinator.backToHome()
        try await Task.sleep(nanoseconds: 200_000_000)
        coordinator.continueBrowsing()
        try await Task.sleep(nanoseconds: 400_000_000)

        XCTAssertEqual(ObjectIdentifier(coordinator.browser.webView), webViewIdentifier)
        XCTAssertEqual(coordinator.browser.webView.url?.absoluteString, loadedURL)
        let firstMarker = try await evaluate(
            "window.__cfSessionMarker",
            in: coordinator.browser.webView
        ) as? String
        XCTAssertEqual(firstMarker, marker, "page JS state was lost after home/game navigation")

        // Recreate the SwiftUI hosting controller and RootView from scratch, as SwiftUI may do
        // when the scene/root view is rebuilt.
        window?.rootViewController = nil
        let newHost = makeHost(coordinator)
        window?.rootViewController = newHost
        newHost.view.frame = window?.bounds ?? UIScreen.main.bounds
        newHost.view.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertEqual(ObjectIdentifier(coordinator.browser.webView), webViewIdentifier)
        XCTAssertEqual(coordinator.browser.webView.url?.absoluteString, loadedURL)
        XCTAssertTrue(coordinator.browser.hasLoadedPage)
        let secondMarker = try await evaluate(
            "window.__cfSessionMarker",
            in: coordinator.browser.webView
        ) as? String
        XCTAssertEqual(secondMarker, marker, "page JS state was lost after SwiftUI host re-creation")
    }

    // MARK: - Helpers

    private func startServer() async throws -> (LocalHTTPServer, UInt16) {
        guard let directory = LocalHTTPServer.testPagesDirectory() else {
            throw PersistenceTestError.missingTestPages
        }
        let server = LocalHTTPServer(rootDirectory: directory)
        let port = try await server.start()
        return (server, port)
    }

    private func primaryURL(_ path: String, port: UInt16) -> URL {
        URL(string: "http://127.0.0.1:\(port)/\(path)")!
    }

    private func load(_ url: URL, in session: BrowserSession) async throws {
        let expectation = XCTestExpectation(description: "load \(url.lastPathComponent)")
        expectation.assertForOverFulfill = false
        var fulfilled = false
        session.onEvent = { event in
            if case .loadFinished = event, !fulfilled {
                fulfilled = true
                expectation.fulfill()
            }
        }
        session.webView.load(URLRequest(url: url))
        await fulfillment(of: [expectation], timeout: 25)
    }

    private func evaluate(_ script: String, in webView: WKWebView) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { value, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: value)
                }
            }
        }
    }

    private func installRootView(_ coordinator: AppCoordinator) throws {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first else {
            throw PersistenceTestError.noWindowScene
        }
        let window = UIWindow(windowScene: scene)
        window.frame = UIScreen.main.bounds
        let host = makeHost(coordinator)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
        self.window = window
    }

    private func makeHost(_ coordinator: AppCoordinator) -> UIHostingController<AnyView> {
        let content = RootView()
            .environmentObject(coordinator)
            .environmentObject(coordinator.settings)
            .environmentObject(coordinator.diagnostics)
        return UIHostingController(rootView: AnyView(content))
    }

    private func waitUntil(
        timeout: TimeInterval,
        interval: TimeInterval = 0.2,
        _ condition: @escaping () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() >= deadline {
                XCTFail("Timed out waiting for condition")
                return
            }
            try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
    }
}

private enum PersistenceTestError: LocalizedError {
    case missingTestPages
    case noWindowScene

    var errorDescription: String? {
        switch self {
        case .missingTestPages: return "TestPages resource missing"
        case .noWindowScene: return "No active UIWindowScene for persistence test"
        }
    }
}
