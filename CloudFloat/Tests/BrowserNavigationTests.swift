import XCTest
@testable import CloudFloat

final class BrowserNavigationTests: XCTestCase {
    private let official = NavigationPolicy()
    private let testDirectory = URL(fileURLWithPath: "/tmp/CloudFloatTestPages")
    private var localPolicy: NavigationPolicy {
        NavigationPolicy(
            allowsLocalTestPages: true,
            localTestHosts: ["127.0.0.1", "localhost"],
            localTestPorts: [8080, 8081],
            allowedFileDirectory: testDirectory
        )
    }

    func testOfficialDomainClassification() {
        XCTAssertTrue(official.isOfficial(host: "sr.mihoyo.com"))
        XCTAssertTrue(official.isOfficial(host: "mihoyo.com"))
        XCTAssertTrue(official.isOfficial(host: "sub.mihoyo.com"))
        XCTAssertTrue(official.isOfficial(host: "SR.MIHOYO.COM."))
        XCTAssertTrue(official.isOfficial(host: "user.hoyoverse.com"))
        XCTAssertTrue(official.isOfficial(host: "hoyolab.com"))

        XCTAssertFalse(official.isOfficial(host: "evilmihoyo.com"))
        XCTAssertFalse(official.isOfficial(host: "mihoyo.com.evil.example"))
        XCTAssertFalse(official.isOfficial(host: "example.com"))
        XCTAssertFalse(official.isOfficial(host: "mihoyo.com@evil.example"))
        XCTAssertFalse(official.isOfficial(host: nil))
        XCTAssertFalse(official.isOfficial(host: "mihoyo.com/path"))
    }

    func testPartnerAuthDomainsAreAllowedInsideWebView() {
        XCTAssertTrue(official.isAllowedPartner(host: "appleid.apple.com"))
        XCTAssertTrue(official.isAllowedPartner(host: "accounts.google.com"))
        XCTAssertTrue(official.isAllowedPartner(host: "login.microsoftonline.com"))
        XCTAssertFalse(official.isAllowedPartner(host: "apple.com.evil.example"))
    }

    func testOfficialNavigationAllowed() throws {
        let url = try XCTUnwrap(URL(string: "https://sr.mihoyo.com/cloud/"))
        XCTAssertEqual(
            official.decision(for: url, context: .linkActivated, isMainFrame: true),
            .allow
        )
        XCTAssertEqual(
            official.decision(for: url, context: .other, isMainFrame: true),
            .allow
        )
    }

    func testUserClickedExternalHTTPSOpensExternally() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/article?token=abc"))
        XCTAssertEqual(
            official.decision(for: url, context: .linkActivated, isMainFrame: true),
            .openExternally(url)
        )
    }

    func testAuthRedirectsOutsideOfficialDomainsStayInsideWebView() throws {
        let url = try XCTUnwrap(URL(string: "https://accounts.google.com/o/oauth2/auth"))
        XCTAssertEqual(
            official.decision(for: url, context: .linkActivated, isMainFrame: true),
            .allow
        )
        let redirect = try XCTUnwrap(URL(string: "https://third-party.example/callback"))
        XCTAssertEqual(
            official.decision(for: redirect, context: .formSubmitted, isMainFrame: true),
            .allow
        )
        XCTAssertEqual(
            official.decision(for: redirect, context: .other, isMainFrame: true),
            .allow
        )
    }

    func testSubframeExternalNavigationAllowed() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/embed"))
        XCTAssertEqual(
            official.decision(for: url, context: .linkActivated, isMainFrame: false),
            .allow
        )
    }

    func testInsecureHTTPBlockedExceptLocalTestServers() throws {
        let http = try XCTUnwrap(URL(string: "http://sr.mihoyo.com/cloud/"))
        XCTAssertEqual(
            official.decision(for: http, context: .other, isMainFrame: true),
            .block(.insecureHTTP)
        )
        let local = try XCTUnwrap(URL(string: "http://127.0.0.1:8080/native-video.html"))
        XCTAssertEqual(
            localPolicy.decision(for: local, context: .other, isMainFrame: true),
            .allow
        )
        XCTAssertEqual(
            official.decision(for: local, context: .other, isMainFrame: true),
            .block(.insecureHTTP)
        )
    }

    func testLocalTestServerPortMustMatch() throws {
        let wrongPort = try XCTUnwrap(URL(string: "http://127.0.0.1:9090/index.html"))
        XCTAssertEqual(
            localPolicy.decision(for: wrongPort, context: .other, isMainFrame: true),
            .block(.insecureHTTP)
        )
        let wrongHost = try XCTUnwrap(URL(string: "http://192.168.1.5:8080/index.html"))
        XCTAssertEqual(
            localPolicy.decision(for: wrongHost, context: .other, isMainFrame: true),
            .block(.insecureHTTP)
        )
    }

    func testFileURLOnlyAllowedInsideTestDirectory() throws {
        let inside = try XCTUnwrap(URL(string: "file:///tmp/CloudFloatTestPages/native-video.html"))
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
            official.decision(for: inside, context: .other, isMainFrame: true),
            .block(.localTestPagesDisabled)
        )
    }

    func testUnsafeSchemesAreBlocked() throws {
        let javascript = try XCTUnwrap(URL(string: "javascript:alert(1)"))
        let data = try XCTUnwrap(URL(string: "data:text/html,<h1>x</h1>"))
        let blob = try XCTUnwrap(URL(string: "blob:https://example.com/abc"))
        let install = try XCTUnwrap(URL(string: "itms-services://?action=download-manifest&url=evil"))
        let custom = try XCTUnwrap(URL(string: "myapp://do-something"))
        for url in [javascript, data, blob, install, custom] {
            let decision = official.decision(for: url, context: .linkActivated, isMainFrame: true)
            if case .allow = decision {
                XCTFail("unsafe scheme should not be allowed: \(url.scheme ?? "")")
            }
            if case .openExternally = decision {
                XCTFail("unsafe scheme should not be opened externally: \(url.scheme ?? "")")
            }
        }
        XCTAssertEqual(
            official.decision(for: install, context: .linkActivated, isMainFrame: true),
            .block(.appInstallScheme)
        )
    }

    func testMailAndTelephoneOpenExternally() throws {
        let mail = try XCTUnwrap(URL(string: "mailto:support@example.com"))
        XCTAssertEqual(
            official.decision(for: mail, context: .linkActivated, isMainFrame: true),
            .openExternally(mail)
        )
        let tel = try XCTUnwrap(URL(string: "tel:10086"))
        XCTAssertEqual(
            official.decision(for: tel, context: .linkActivated, isMainFrame: true),
            .openExternally(tel)
        )
    }

    func testNilAndAboutBlankAreAllowed() throws {
        XCTAssertEqual(official.decision(for: nil, context: .other, isMainFrame: true), .allow)
        let blank = try XCTUnwrap(URL(string: "about:blank"))
        XCTAssertEqual(official.decision(for: blank, context: .other, isMainFrame: true), .allow)
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
        XCTAssertTrue(
            TLSErrorClassifier.isTLSFailure(
                domain: NSURLErrorDomain,
                code: NSURLErrorAppTransportSecurityRequiresSecureConnection
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
            host: "sr.mihoyo.com",
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
