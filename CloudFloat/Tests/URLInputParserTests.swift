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

    func testParsesBareIPAddress() {
        XCTAssertEqual(
            URLInputParser.url(from: "192.168.1.10"),
            URL(string: "https://192.168.1.10")
        )
    }

    func testParsesIPAddressWithPort() {
        XCTAssertEqual(
            URLInputParser.url(from: "192.168.1.10:8080/status"),
            URL(string: "https://192.168.1.10:8080/status")
        )
    }

    func testParsesWWWAndSubdomainHosts() {
        XCTAssertEqual(
            URLInputParser.url(from: "www.example.com"),
            URL(string: "https://www.example.com")
        )
        XCTAssertEqual(
            URLInputParser.url(from: "news.ycombinator.com/item?id=1"),
            URL(string: "https://news.ycombinator.com/item?id=1")
        )
    }

    func testSearchTextIsDelegatedToSearchNotParsedAsURL() {
        // Keyword input must not be treated as a host; AppCoordinator falls back to the
        // configured search engine.
        XCTAssertNil(URLInputParser.url(from: "今天天气怎么样"))
        XCTAssertNil(URLInputParser.url(from: "swiftui webkit pip"))
    }
}
