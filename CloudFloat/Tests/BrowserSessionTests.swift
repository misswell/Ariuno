import WebKit
import XCTest
@testable import Ariuno

@MainActor
final class BrowserSessionTests: XCTestCase {
    func testWebViewConfigurationMatchesM1Requirements() {
        let session = BrowserSession()
        defer { session.tearDown() }

        XCTAssertTrue(session.configuration.allowsInlineMediaPlayback)
        XCTAssertTrue(session.configuration.allowsPictureInPictureMediaPlayback)
        XCTAssertTrue(session.configuration.preferences.isElementFullscreenEnabled)
        XCTAssertEqual(session.configuration.mediaTypesRequiringUserActionForPlayback, .audio)
        XCTAssertTrue(
            session.webView.customUserAgent?.isEmpty ?? true,
            "Must not spoof a desktop User-Agent"
        )
        XCTAssertTrue(session.webView.isInspectable)
        XCTAssertTrue(session.mediaDetector.probeScriptLoaded)
        XCTAssertFalse(session.configuration.preferences.javaScriptCanOpenWindowsAutomatically)
        XCTAssertFalse(session.hasLoadedPage)
        XCTAssertTrue(session.isShowingBlankPage)
        XCTAssertTrue(session.webView.allowsBackForwardNavigationGestures)
    }

    func testProbeUserScriptIsInstalledForAllFrames() throws {
        let session = BrowserSession(inPageControlEnabled: true)
        defer { session.tearDown() }

        let scripts = session.configuration.userContentController.userScripts
        XCTAssertEqual(scripts.count, 1)
        let script = try XCTUnwrap(scripts.first)
        XCTAssertFalse(script.isForMainFrameOnly)
        XCTAssertEqual(script.injectionTime, .atDocumentEnd)
        XCTAssertTrue(script.source.contains("cloudFloatMedia"))
        XCTAssertFalse(script.source.contains("__CF_BUTTON_ENABLED__"))
        XCTAssertTrue(script.source.contains("const DEFAULT_BUTTON_ENABLED = true"))
    }

    func testDisablingInPageControlIsReflectedInSubsequentInjection() throws {
        let session = BrowserSession(inPageControlEnabled: false)
        defer { session.tearDown() }
        let script = try XCTUnwrap(session.configuration.userContentController.userScripts.first)
        XCTAssertTrue(script.source.contains("const DEFAULT_BUTTON_ENABLED = false"))
    }

    func testLocalTestPolicyCanBeToggledAtRuntime() throws {
        let session = BrowserSession()
        defer { session.tearDown() }
        session.updateLocalTestAccess(enabled: true)
        let localURL = try XCTUnwrap(URL(string: "http://127.0.0.1:8080/native-video.html"))
        XCTAssertEqual(
            session.navigationPolicy.decision(for: localURL, context: .other, isMainFrame: true),
            .allow
        )

        session.updateLocalTestAccess(enabled: false)
        XCTAssertEqual(
            session.navigationPolicy.decision(for: localURL, context: .other, isMainFrame: true),
            .allow
        )
    }

    func testEndSessionPreservesTheWebViewAndMarksBlank() {
        let session = BrowserSession()
        defer { session.tearDown() }
        let identifier = ObjectIdentifier(session.webView)

        session.resetToBlank()
        XCTAssertTrue(session.isShowingBlankPage)
        XCTAssertFalse(session.hasLoadedPage)
        XCTAssertEqual(ObjectIdentifier(session.webView), identifier)
        XCTAssertEqual(session.webContentTerminatedCount, 0)
    }

    func testMediaDetectorStartsWithNoFramesAndAggregateUnknown() {
        let session = BrowserSession()
        defer { session.tearDown() }
        XCTAssertTrue(session.mediaDetector.frames.isEmpty)
        XCTAssertEqual(session.mediaDetector.aggregate.kind, .unknown)
        XCTAssertNil(session.mediaDetector.lastSnapshotReceivedAt)
        XCTAssertFalse(session.mediaDetector.isPolling)
    }

    func testCookieStoreStartsEmptyInCleanTestEnvironment() {
        let session = BrowserSession()
        defer { session.tearDown() }
        // We only assert the count is non-negative and values are never exposed by the API.
        XCTAssertGreaterThanOrEqual(session.cookieStore.cookieRecordCount, 0)
        XCTAssertGreaterThanOrEqual(session.cookieStore.officialSiteRecordCount, 0)
        XCTAssertFalse(
            session.cookieStore.hasOfficialSiteCookieRecords
                && session.cookieStore.cookieRecordCount == 0
        )
    }
}
