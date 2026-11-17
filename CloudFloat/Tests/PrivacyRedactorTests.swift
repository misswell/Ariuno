import XCTest
@testable import Ariuno

final class PrivacyRedactorTests: XCTestCase {
    func testURLsAreReducedToOrigin() {
        let input = "GET https://user:pass@sr.mihoyo.com/cloud/login?token=abc123&uid=42#fragment failed"
        let output = PrivacyRedactor.redact(input)
        XCTAssertTrue(output.contains("https://sr.mihoyo.com"))
        XCTAssertFalse(output.contains("abc123"))
        XCTAssertFalse(output.contains("uid=42"))
        XCTAssertFalse(output.contains("/cloud/login"))
        XCTAssertFalse(output.contains("fragment"))
        XCTAssertFalse(output.contains("user:pass"))
    }

    func testURLWithPortKeepsPortOnly() {
        let url = URL(string: "http://127.0.0.1:8080/nested-iframe.html?child=secret")!
        XCTAssertEqual(PrivacyRedactor.redactURL(url), "http://127.0.0.1:8080")
        XCTAssertEqual(
            PrivacyRedactor.redactURLString("https://sr.mihoyo.com/a/b?token=x"),
            "https://sr.mihoyo.com"
        )
    }

    func testAuthorizationAndCookieHeadersAreRemoved() {
        let input = """
        Authorization: Bearer abc.def.ghi
        Cookie: ltoken=verysecret; mid=123456789
        Set-Cookie: cookie_token=hidden; Path=/
        """
        let output = PrivacyRedactor.redact(input)
        XCTAssertFalse(output.contains("abc.def.ghi"))
        XCTAssertFalse(output.contains("verysecret"))
        XCTAssertFalse(output.contains("123456789"))
        XCTAssertFalse(output.contains("hidden"))
        XCTAssertTrue(output.contains("<redacted-header>"))
    }

    func testCredentialKeyValuePairsAreRemovedButKeyKept() {
        let input = "token=abc123&login_ticket=xyz&password=hunter2&account_id=999"
        let output = PrivacyRedactor.redact(input)
        XCTAssertTrue(output.contains("token=<redacted>"))
        XCTAssertTrue(output.contains("login_ticket=<redacted>"))
        XCTAssertFalse(output.contains("abc123"))
        XCTAssertFalse(output.contains("xyz"))
        XCTAssertFalse(output.contains("hunter2"))
        XCTAssertFalse(output.contains("999"))
    }

    func testEmailsPhonesAndJWTsAreRemoved() {
        let input = """
        contact test.user+tag@example.com or 13800138000
        jwt eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.abcdefghijklmnopqrstuvwxyz
        """
        let output = PrivacyRedactor.redact(input)
        XCTAssertFalse(output.contains("test.user+tag@example.com"))
        XCTAssertFalse(output.contains("13800138000"))
        XCTAssertFalse(output.contains("eyJhbGciOiJIUzI1NiJ9"))
        XCTAssertTrue(output.contains("<redacted-email>"))
        XCTAssertTrue(output.contains("<redacted-phone>"))
        XCTAssertTrue(output.contains("<redacted-jwt>"))
    }

    func testUUIDsAndLongSecretsAreRemoved() {
        let input = "id 123e4567-e89b-12d3-a456-426614174000 secret ABCDEF0123456789abcdef0123456789ABCDEF"
        let output = PrivacyRedactor.redact(input)
        XCTAssertFalse(output.contains("123e4567-e89b-12d3-a456-426614174000"))
        XCTAssertFalse(output.contains("ABCDEF0123456789abcdef0123456789ABCDEF"))
        XCTAssertTrue(output.contains("<redacted-id>"))
        XCTAssertTrue(output.contains("<redacted-secret>"))
    }

    func testMetadataSensitiveKeysAreRedacted() {
        let output = PrivacyRedactor.redact(metadata: [
            "cookie": "ltoken=secret",
            "authorization": "Bearer abc",
            "access_token": "xyz",
            "host": "sr.mihoyo.com",
            "note": "token=abc123",
            "count": "3"
        ])
        XCTAssertEqual(output["cookie"], "<redacted>")
        XCTAssertEqual(output["authorization"], "<redacted>")
        XCTAssertEqual(output["access_token"], "<redacted>")
        XCTAssertEqual(output["host"], "sr.mihoyo.com")
        XCTAssertEqual(output["note"], "token=<redacted>")
        XCTAssertEqual(output["count"], "3")
    }

    func testBenignTextRemainsReadable() {
        let input = "页面加载完成 host=sr.mihoyo.com count=3 duration=12s"
        XCTAssertEqual(PrivacyRedactor.redact(input), input)
    }

    func testSensitiveKeyDetection() {
        XCTAssertTrue(PrivacyRedactor.isSensitiveKey("Authorization"))
        XCTAssertTrue(PrivacyRedactor.isSensitiveKey("access_token"))
        XCTAssertTrue(PrivacyRedactor.isSensitiveKey("cookie"))
        XCTAssertTrue(PrivacyRedactor.isSensitiveKey("login_ticket"))
        XCTAssertTrue(PrivacyRedactor.isSensitiveKey("email"))
        XCTAssertFalse(PrivacyRedactor.isSensitiveKey("host"))
        XCTAssertFalse(PrivacyRedactor.isSensitiveKey("frameCount"))
        XCTAssertFalse(PrivacyRedactor.isSensitiveKey("errorCode"))
    }

    func testEmptyAndMalformedURLsDoNotCrash() {
        XCTAssertEqual(PrivacyRedactor.redact(""), "")
        XCTAssertFalse(PrivacyRedactor.redact("https://").isEmpty)
        XCTAssertEqual(PrivacyRedactor.redactURLString("not a url"), "<redacted-url>")
    }
}
