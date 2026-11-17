import XCTest
@testable import Ariuno

@MainActor
final class LocalHTTPServerTests: XCTestCase {
    private func startServer() async throws -> (LocalHTTPServer, UInt16) {
        guard let directory = LocalHTTPServer.testPagesDirectory() else {
            throw LocalHTTPServer.ServerError.testPagesMissing
        }
        let server = LocalHTTPServer(rootDirectory: directory)
        let port = try await server.start()
        return (server, port)
    }

    func testTestPagesDirectoryContainsRequiredFiles() throws {
        guard let directory = LocalHTTPServer.testPagesDirectory() else {
            XCTFail("TestPages resource is missing from the host app bundle")
            return
        }
        for name in ["native-video.html", "canvas-only.html", "nested-iframe.html", "sample.mp4"] {
            let url = directory.appendingPathComponent(name)
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: url.path),
                "Missing test resource \(name)"
            )
        }
    }

    func testServesHTMLAndVideoWithCorrectMIME() async throws {
        let (server, port) = try await startServer()
        defer { server.stop() }

        let htmlURL = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/native-video.html"))
        var request = URLRequest(url: htmlURL)
        request.timeoutInterval = 15
        let (htmlData, htmlResponse) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((htmlResponse as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(
            (htmlResponse as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type"),
            "text/html; charset=utf-8"
        )
        let html = try XCTUnwrap(String(data: htmlData, encoding: .utf8))
        XCTAssertTrue(html.contains("<video"))
        XCTAssertTrue(html.contains("CloudFloat"))

        let videoURL = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/sample.mp4"))
        var videoRequest = URLRequest(url: videoURL)
        videoRequest.timeoutInterval = 15
        let (_, videoResponse) = try await URLSession.shared.data(for: videoRequest)
        XCTAssertEqual((videoResponse as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(
            (videoResponse as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type"),
            "video/mp4"
        )
        let length = Int(
            (videoResponse as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Length") ?? "0"
        ) ?? 0
        XCTAssertGreaterThan(length, 100_000)
    }

    func testRangeRequestReturnsPartialContent() async throws {
        let (server, port) = try await startServer()
        defer { server.stop() }

        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/sample.mp4"))
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("bytes=100-199", forHTTPHeaderField: "Range")
        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse
        XCTAssertEqual(http?.statusCode, 206)
        XCTAssertEqual(data.count, 100)
        let contentRange = http?.value(forHTTPHeaderField: "Content-Range") ?? ""
        XCTAssertTrue(contentRange.hasPrefix("bytes 100-199/"))
    }

    func testMissingFileReturns404AndTraversalIsNotServed() async throws {
        let (server, port) = try await startServer()
        defer { server.stop() }

        let missing = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/does-not-exist.html"))
        let (_, missingResponse) = try await URLSession.shared.data(from: missing)
        XCTAssertEqual((missingResponse as? HTTPURLResponse)?.statusCode, 404)

        // Percent-encoded traversal: regardless of URLSession normalisation, the secret file
        // must never be served with a 200.
        let traversal = try XCTUnwrap(
            URL(string: "http://127.0.0.1:\(port)/%2e%2e/Info.plist")
        )
        let (_, traversalResponse) = try await URLSession.shared.data(from: traversal)
        XCTAssertNotEqual((traversalResponse as? HTTPURLResponse)?.statusCode, 200)
    }

    func testTwoServersUseDistinctLoopbackPorts() async throws {
        let (first, firstPort) = try await startServer()
        let (second, secondPort) = try await startServer()
        defer {
            first.stop()
            second.stop()
        }
        XCTAssertNotEqual(firstPort, secondPort)

        let firstURL = try XCTUnwrap(URL(string: "http://127.0.0.1:\(firstPort)/canvas-only.html"))
        let secondURL = try XCTUnwrap(URL(string: "http://127.0.0.1:\(secondPort)/canvas-only.html"))
        let (firstData, firstResponse) = try await URLSession.shared.data(from: firstURL)
        let (secondData, secondResponse) = try await URLSession.shared.data(from: secondURL)
        XCTAssertEqual((firstResponse as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual((secondResponse as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(firstData, secondData)
    }

    func testRangeParser() {
        XCTAssertEqual(LocalHTTPServer.parseRange("bytes=0-99", totalLength: 1000), 0..<100)
        XCTAssertEqual(LocalHTTPServer.parseRange("bytes=100-", totalLength: 1000), 100..<1000)
        XCTAssertEqual(LocalHTTPServer.parseRange("bytes=-100", totalLength: 1000), 900..<1000)
        XCTAssertEqual(LocalHTTPServer.parseRange("bytes=900-2000", totalLength: 1000), 900..<1000)
        XCTAssertNil(LocalHTTPServer.parseRange("bytes=1000-", totalLength: 1000))
        XCTAssertNil(LocalHTTPServer.parseRange("items=0-10", totalLength: 1000))
        XCTAssertNil(LocalHTTPServer.parseRange("bytes=abc-def", totalLength: 1000))
    }

    func testMIMETypes() {
        XCTAssertEqual(
            LocalHTTPServer.mimeType(forExtension: "HTML"),
            "text/html; charset=utf-8"
        )
        XCTAssertEqual(
            LocalHTTPServer.mimeType(forExtension: "js"),
            "application/javascript; charset=utf-8"
        )
        XCTAssertEqual(LocalHTTPServer.mimeType(forExtension: "mp4"), "video/mp4")
        XCTAssertEqual(
            LocalHTTPServer.mimeType(forExtension: "bin"),
            "application/octet-stream"
        )
    }
}
