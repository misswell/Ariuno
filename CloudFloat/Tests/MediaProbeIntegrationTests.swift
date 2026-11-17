import UIKit
import WebKit
import XCTest
@testable import Ariuno

@MainActor
final class MediaProbeIntegrationTests: XCTestCase {
    private var harness: ProbeHarness?

    override func tearDown() {
        harness?.shutdown()
        harness = nil
        super.tearDown()
    }

    func testNativeVideoPageReportsSnapshotThroughWKScriptMessageHandler() async throws {
        let harness = try await makeHarness()
        self.harness = harness

        let expectation = XCTestExpectation(description: "native video snapshot")
        expectation.assertForOverFulfill = false
        harness.detector.onSnapshot = { _, snapshot in
            if snapshot.isTopFrame && snapshot.videoCount >= 1 {
                expectation.fulfill()
            }
        }

        harness.webView.load(URLRequest(url: harness.primaryURL("native-video.html")))
        await fulfillment(of: [expectation], timeout: 25)

        let topSnapshot = harness.detector.frames.values.first(where: \.isTopFrame)
        XCTAssertNotNil(topSnapshot)
        XCTAssertEqual(topSnapshot?.origin, "http://127.0.0.1:\(harness.primaryPort)")
        XCTAssertGreaterThanOrEqual(topSnapshot?.videoCount ?? 0, 1)
        XCTAssertFalse(topSnapshot?.videos.isEmpty ?? true)
        XCTAssertNotNil(topSnapshot?.videos.first?.readyState)
        XCTAssertNotNil(topSnapshot?.videos.first?.pipSupported)
        XCTAssertEqual(topSnapshot?.pageKind, "media")

        let probeType = try await evaluate(
            "typeof window.__cloudFloatProbe.requestPiP",
            in: harness.webView
        )
        XCTAssertEqual(probeType as? String, "function")
        let buttonAPI = try await evaluate(
            "typeof window.__cloudFloatProbe.setButtonEnabled",
            in: harness.webView
        )
        XCTAssertEqual(buttonAPI as? String, "function")
    }

    func testMediaEventsReachNativeBridge() async throws {
        let harness = try await makeHarness()
        self.harness = harness

        let expectation = XCTestExpectation(description: "media playback event")
        expectation.assertForOverFulfill = false
        harness.detector.onEvent = { event in
            if event.name == .playing || event.name == .loadedmetadata || event.name == .loadeddata {
                expectation.fulfill()
            }
        }

        harness.webView.load(URLRequest(url: harness.primaryURL("native-video.html")))
        await fulfillment(of: [expectation], timeout: 25)

        let event = harness.detector.lastPlaybackEvent
        XCTAssertNotNil(event)
        XCTAssertEqual(event?.origin, "http://127.0.0.1:\(harness.primaryPort)")
    }

    func testCanvasOnlyPageIsClassifiedAsCanvasAndHasNoVideo() async throws {
        let harness = try await makeHarness()
        self.harness = harness

        let expectation = XCTestExpectation(description: "canvas snapshot")
        expectation.assertForOverFulfill = false
        harness.detector.onSnapshot = { _, snapshot in
            if snapshot.isTopFrame && snapshot.canvasCount >= 1 {
                expectation.fulfill()
            }
        }

        harness.webView.load(URLRequest(url: harness.primaryURL("canvas-only.html")))
        await fulfillment(of: [expectation], timeout: 25)

        let topSnapshot = harness.detector.frames.values.first(where: \.isTopFrame)
        XCTAssertEqual(topSnapshot?.videoCount, 0)
        XCTAssertGreaterThanOrEqual(topSnapshot?.canvasCount ?? 0, 1)
        XCTAssertEqual(harness.detector.aggregate.kind, .canvas)
        XCTAssertFalse(harness.detector.aggregate.hasAnyVideo)
        XCTAssertFalse(harness.detector.aggregate.hasPiPCapablePlayingVideo)
    }

    func testNestedCrossOriginIframeIsProbedIndependently() async throws {
        let harness = try await makeHarness()
        self.harness = harness

        var components = URLComponents(
            url: harness.primaryURL("nested-iframe.html"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(
                name: "child",
                value: harness.secondaryURL("native-video.html").absoluteString
            )
        ]
        let nestedURL = try XCTUnwrap(components?.url)

        let expectation = XCTestExpectation(description: "cross-origin child snapshot")
        expectation.assertForOverFulfill = false
        harness.detector.onSnapshot = { _, snapshot in
            if !snapshot.isTopFrame && snapshot.videoCount >= 1 {
                expectation.fulfill()
            }
        }

        harness.webView.load(URLRequest(url: nestedURL))
        await fulfillment(of: [expectation], timeout: 30)

        try await waitUntil(timeout: 15) {
            harness.detector.frames.values.contains(where: \.isTopFrame)
                && Set(harness.detector.frames.values.map(\.origin)).count >= 2
        }

        let origins = Set(harness.detector.frames.values.map(\.origin))
        XCTAssertTrue(origins.contains("http://127.0.0.1:\(harness.primaryPort)"))
        XCTAssertTrue(origins.contains("http://127.0.0.1:\(harness.secondaryPort)"))

        let top = harness.detector.frames.values.first(where: \.isTopFrame)
        XCTAssertGreaterThanOrEqual(top?.iframeCount ?? 0, 1)

        let child = harness.detector.frames.values.first {
            !$0.isTopFrame && $0.videoCount >= 1
        }
        XCTAssertNotNil(child)
        XCTAssertEqual(child?.origin, "http://127.0.0.1:\(harness.secondaryPort)")
        XCTAssertGreaterThanOrEqual(child?.videos.count ?? 0, 1)
        XCTAssertEqual(harness.detector.aggregate.kind, .htmlVideo)
        XCTAssertGreaterThanOrEqual(harness.detector.aggregate.frameCount, 2)
        // The subframe owns the video; native evaluateJavaScript cannot reach it. PiP
        // support itself may be false on the simulator, but the frame ownership must hold.
        XCTAssertFalse(harness.detector.aggregate.mainFrameHasPiPCapablePlayingVideo)
    }

    func testInjectedControlIsNotShownWhenSettingDisabled() async throws {
        let harness = try await makeHarness(inPageControlEnabled: false)
        self.harness = harness

        let expectation = XCTestExpectation(description: "snapshot with disabled control")
        expectation.assertForOverFulfill = false
        harness.detector.onSnapshot = { _, snapshot in
            if snapshot.isTopFrame && snapshot.videoCount >= 1 {
                expectation.fulfill()
            }
        }
        harness.webView.load(URLRequest(url: harness.primaryURL("native-video.html")))
        await fulfillment(of: [expectation], timeout: 25)

        let hostExists = try await evaluate(
            "document.getElementById('cf-pip-host') !== null",
            in: harness.webView
        )
        XCTAssertEqual(hostExists as? Bool, false)
    }


    func testTestPageChineseTextIsDecodedAndRendered() async throws {
        let harness = try await makeHarness()
        self.harness = harness

        let expectation = XCTestExpectation(description: "page loaded")
        expectation.assertForOverFulfill = false
        harness.detector.onSnapshot = { _, snapshot in
            if snapshot.isTopFrame && snapshot.videoCount >= 1 {
                expectation.fulfill()
            }
        }
        harness.webView.load(URLRequest(url: harness.primaryURL("native-video.html")))
        await fulfillment(of: [expectation], timeout: 25)

        let heading = try await evaluate(
            "document.querySelector('h1') && document.querySelector('h1').textContent",
            in: harness.webView
        ) as? String
        XCTAssertEqual(heading, "原生 HTML5 视频 PiP 测试")

        let fontFamily = try await evaluate(
            "getComputedStyle(document.body).fontFamily",
            in: harness.webView
        ) as? String
        XCTAssertNotNil(fontFamily)

        XCTAssertFalse(fontFamily?.isEmpty ?? true)
    }

    // MARK: - Harness

    private func makeHarness(inPageControlEnabled: Bool = true) async throws -> ProbeHarness {
        guard let directory = LocalHTTPServer.testPagesDirectory() else {
            throw ProbeHarnessError.missingTestPages
        }
        let primaryServer = LocalHTTPServer(rootDirectory: directory)
        let primaryPort = try await primaryServer.start()
        let secondaryServer = LocalHTTPServer(rootDirectory: directory)
        let secondaryPort: UInt16
        do {
            secondaryPort = try await secondaryServer.start()
        } catch {
            primaryServer.stop()
            throw error
        }

        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first else {
            primaryServer.stop()
            secondaryServer.stop()
            throw ProbeHarnessError.noWindowScene
        }

        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.websiteDataStore = .nonPersistent()
        configuration.mediaTypesRequiringUserActionForPlayback = .audio

        let detector = MediaDetector(
            configuration: configuration,
            inPageControlEnabled: inPageControlEnabled
        )
        let webView = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 390, height: 700),
            configuration: configuration
        )
        detector.attach(webView: webView)

        let window = UIWindow(windowScene: scene)
        window.frame = UIScreen.main.bounds
        let root = UIViewController()
        root.view.backgroundColor = .black
        window.rootViewController = root
        window.makeKeyAndVisible()
        root.view.addSubview(webView)
        detector.startPolling()

        return ProbeHarness(
            primaryServer: primaryServer,
            secondaryServer: secondaryServer,
            primaryPort: primaryPort,
            secondaryPort: secondaryPort,
            detector: detector,
            webView: webView,
            window: window
        )
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

private enum ProbeHarnessError: LocalizedError {
    case missingTestPages
    case noWindowScene

    var errorDescription: String? {
        switch self {
        case .missingTestPages: return "TestPages resource missing"
        case .noWindowScene: return "No active UIWindowScene for WKWebView test host"
        }
    }
}

@MainActor
private final class ProbeHarness {
    let primaryServer: LocalHTTPServer
    let secondaryServer: LocalHTTPServer
    let primaryPort: UInt16
    let secondaryPort: UInt16
    let detector: MediaDetector
    let webView: WKWebView
    let window: UIWindow
    private var isShutDown = false

    init(
        primaryServer: LocalHTTPServer,
        secondaryServer: LocalHTTPServer,
        primaryPort: UInt16,
        secondaryPort: UInt16,
        detector: MediaDetector,
        webView: WKWebView,
        window: UIWindow
    ) {
        self.primaryServer = primaryServer
        self.secondaryServer = secondaryServer
        self.primaryPort = primaryPort
        self.secondaryPort = secondaryPort
        self.detector = detector
        self.webView = webView
        self.window = window
    }

    func primaryURL(_ path: String) -> URL {
        URL(string: "http://127.0.0.1:\(primaryPort)/\(path)")!
    }

    func secondaryURL(_ path: String) -> URL {
        URL(string: "http://127.0.0.1:\(secondaryPort)/\(path)")!
    }

    func shutdown() {
        guard !isShutDown else { return }
        isShutDown = true
        detector.stopPolling()
        detector.shutdown()
        webView.stopLoading()
        webView.removeFromSuperview()
        window.isHidden = true
        window.rootViewController = nil
        primaryServer.stop()
        secondaryServer.stop()
    }
}
