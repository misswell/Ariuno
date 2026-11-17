import XCTest
@testable import Ariuno

final class BrowserNavigationTests: XCTestCase {
    private let policy = NavigationPolicy()
    private let testDirectory = URL(fileURLWithPath: "/tmp/AriunoTestPages")
    private var localPolicy: NavigationPolicy {
        NavigationPolicy(
            allowsLocalTestPages: true,
            localTestHosts: ["127.0.0.1", "localhost"],
            localTestPorts: [8080, 8081],
            allowedFileDirectory: testDirectory
        )
    }

    func testHTTPAndHTTPSStayInApp() throws {
        let https = try XCTUnwrap(URL(string: "https://example.com/article?token=abc"))
        let http = try XCTUnwrap(URL(string: "http://example.com/insecure"))
        for url in [https, http] {
            for context in [NavigationContext.linkActivated, .formSubmitted, .other] {
                XCTAssertEqual(
                    policy.decision(for: url, context: context, isMainFrame: true),
                    .allow,
                    "\(url) \(context) should stay in-app"
                )
            }
        }
    }

    func testCloudGameURLIsNotSpecial() throws {
        let url = try XCTUnwrap(URL(string: "https://sr.mihoyo.com/cloud/"))
        for context in [NavigationContext.linkActivated, .formSubmitted, .other] {
            XCTAssertEqual(
                policy.decision(for: url, context: context, isMainFrame: true),
                .allow
            )
        }
    }

    func testSubframeNavigationStaysInApp() throws {
        let url = try XCTUnwrap(URL(string: "https://ads.example.com/embed"))
        XCTAssertEqual(
            policy.decision(for: url, context: .linkActivated, isMainFrame: false),
            .allow
        )
    }

    func testLocalTestServerPortMustMatch() throws {
        let right = try XCTUnwrap(URL(string: "http://127.0.0.1:8080/native-video.html"))
        XCTAssertEqual(
            localPolicy.decision(for: right, context: .other, isMainFrame: true),
            .allow
        )
        let wrongPort = try XCTUnwrap(URL(string: "http://127.0.0.1:9090/index.html"))
        XCTAssertEqual(
            localPolicy.decision(for: wrongPort, context: .other, isMainFrame: true),
            .allow
        )
        let wrongHost = try XCTUnwrap(URL(string: "http://192.168.1.5:8080/index.html"))
        XCTAssertEqual(
            localPolicy.decision(for: wrongHost, context: .other, isMainFrame: true),
            .allow
        )
    }

    func testFileURLOnlyAllowedInsideTestDirectory() throws {
        let inside = try XCTUnwrap(URL(string: "file:///tmp/AriunoTestPages/native-video.html"))
        XCTAssertEqual(
            localPolicy.decision(for: inside, context: .other, isMainFrame: true),
            .allow
        )
        let outside = try XCTUnwrap(URL(string: "file:///tmp/secret.txt"))
        XCTAssertEqual(
            localPolicy.decision(for: outside, context: .other, isMainFrame: true),
            .block(.fileOutsideAllowedScope)
        )
        XCTAssertEqual(
            policy.decision(for: inside, context: .other, isMainFrame: true),
            .block(.localTestPagesDisabled)
        )
    }

    func testSystemSchemesOpenExternally() throws {
        let mail = try XCTUnwrap(URL(string: "mailto:support@example.com"))
        let tel = try XCTUnwrap(URL(string: "tel:10086"))
        XCTAssertEqual(
            policy.decision(for: mail, context: .linkActivated, isMainFrame: true),
            .openExternally(mail)
        )
        XCTAssertEqual(
            policy.decision(for: tel, context: .linkActivated, isMainFrame: true),
            .openExternally(tel)
        )
        XCTAssertEqual(
            policy.decision(for: mail, context: .linkActivated, isMainFrame: false),
            .block(.unsafeScheme)
        )
    }

    func testUnsafeSchemesAreBlocked() throws {
        let javascript = try XCTUnwrap(URL(string: "javascript:alert(1)"))
        let data = try XCTUnwrap(URL(string: "data:text/html,<h1>x</h1>"))
        let blob = try XCTUnwrap(URL(string: "blob:https://example.com/abc"))
        let install = try XCTUnwrap(URL(string: "itms-services://?action=download-manifest&url=evil"))
        let custom = try XCTUnwrap(URL(string: "myapp://do-something"))
        for url in [javascript, data, blob, install, custom] {
            let decision = policy.decision(for: url, context: .linkActivated, isMainFrame: true)
            if case .allow = decision {
                XCTFail("unsafe scheme should not be allowed: \(url.scheme ?? "")")
            }
            if case .openExternally = decision {
                XCTFail("unsafe scheme should not be opened externally: \(url.scheme ?? "")")
            }
        }
        XCTAssertEqual(
            policy.decision(for: install, context: .linkActivated, isMainFrame: true),
            .block(.appInstallScheme)
        )
    }

    func testNilAndAboutBlankAreAllowed() throws {
        XCTAssertEqual(policy.decision(for: nil, context: .other, isMainFrame: true), .allow)
        let blank = try XCTUnwrap(URL(string: "about:blank"))
        XCTAssertEqual(policy.decision(for: blank, context: .other, isMainFrame: true), .allow)
    }

    func testTLSErrorClassification() {
        XCTAssertTrue(
            TLSErrorClassifier.isTLSFailure(
                domain: NSURLErrorDomain,
                code: NSURLErrorServerCertificateUntrusted
            )
        )
        XCTAssertTrue(
            TLSErrorClassifier.isTLSFailure(
                domain: NSURLErrorDomain,
                code: NSURLErrorSecureConnectionFailed
            )
        )
        XCTAssertFalse(
            TLSErrorClassifier.isTLSFailure(
                domain: NSURLErrorDomain,
                code: NSURLErrorCancelled
            )
        )
        XCTAssertFalse(
            TLSErrorClassifier.isTLSFailure(
                domain: "OtherDomain",
                code: NSURLErrorServerCertificateUntrusted
            )
        )
    }

    func testTLSUserMessageExplicitlyRefusesBypass() {
        let failure = BrowserNavigationFailure(
            code: NSURLErrorServerCertificateUntrusted,
            message: "untrusted",
            host: "example.com",
            isTLSError: true,
            isCancelled: false,
            isProvisional: true
        )
        let message = TLSErrorClassifier.userMessage(for: failure)
        XCTAssertTrue(message.contains("证书"))
        XCTAssertTrue(message.contains("不会忽略"))
    }

    func testNavigationContextMapping() {
        XCTAssertEqual(NavigationContext(webKitType: .linkActivated), .linkActivated)
        XCTAssertEqual(NavigationContext(webKitType: .formSubmitted), .formSubmitted)
        XCTAssertEqual(NavigationContext(webKitType: .backForward), .backForward)
        XCTAssertEqual(NavigationContext(webKitType: .reload), .reload)
        XCTAssertEqual(NavigationContext(webKitType: .formResubmitted), .formSubmitted)
        XCTAssertEqual(NavigationContext(webKitType: .other), .other)
    }
}
