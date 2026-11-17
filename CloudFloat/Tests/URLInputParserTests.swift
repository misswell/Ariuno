import XCTest
@testable import Ariuno

final class URLInputParserTests: XCTestCase {
    func testParsesFullHTTPSURL() {
        XCTAssertEqual(
            URLInputParser.url(from: "https://example.com/cloud"),
            URL(string: "https://example.com/cloud")
        )
    }

    func testAddsHTTPSForHostLikeInput() {
        XCTAssertEqual(
            URLInputParser.url(from: "example.com"),
            URL(string: "https://example.com")
        )
        XCTAssertEqual(
            URLInputParser.url(from: "example.com/cloud?x=1"),
            URL(string: "https://example.com/cloud?x=1")
        )
    }

    func testAddsHTTPSForLocalhostWithPort() {
        XCTAssertEqual(
            URLInputParser.url(from: "localhost:8080/page"),
            URL(string: "https://localhost:8080/page")
        )
    }

    func testKeepsLocalHTTPTestServers() {
        XCTAssertEqual(
            URLInputParser.url(from: "http://127.0.0.1:8080/native-video.html"),
            URL(string: "http://127.0.0.1:8080/native-video.html")
        )
    }

    func testRejectsPlainTextQueriesAndEmptyInput() {
        XCTAssertNil(URLInputParser.url(from: ""))
        XCTAssertNil(URLInputParser.url(from: "   "))
        XCTAssertNil(URLInputParser.url(from: "cloud game"))
        XCTAssertNil(URLInputParser.url(from: "about:blank"))
    }

    func testRejectsUnsafeSchemes() {
        XCTAssertNil(URLInputParser.url(from: "javascript:alert(1)"))
        XCTAssertNil(URLInputParser.url(from: "itms-services://example"))
    }
}
