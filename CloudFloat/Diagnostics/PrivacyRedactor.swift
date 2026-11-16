import Foundation

/// Best-effort scrubbing for anything that reaches the diagnostics log or an export.
///
/// Rules are intentionally conservative:
/// - URLs are reduced to `scheme://host`; paths, query strings and fragments are dropped
///   because they routinely contain one-time login tickets and tokens.
/// - Credential-looking key/value pairs, cookies, bearer tokens, JWTs, e-mail addresses,
///   phone numbers, UUIDs and long secret-like literals are replaced.
///
/// The redactor is defense-in-depth, not a licence to log secrets. Call sites must still
/// avoid reading or forwarding cookies, tokens and full URLs.
enum PrivacyRedactor {
    static let replacement = "<redacted>"

    private static let sensitiveKeyFragments: [String] = [
        "authorization", "cookie", "token", "password", "passwd", "passphrase",
        "secret", "sessionid", "session_id", "sessionkey", "session_key",
        "login_ticket", "loginticket", "stoken", "ltoken", "cookie_token",
        "account_id", "accountid", "game_uid", "gameuid", "uid", "mid",
        "email", "mail", "phone", "mobile", "credential", "api_key", "apikey",
        "access_key", "refresh", "jwt", "bearer", "signature", "sign"
    ]

    private struct RegexRule {
        let expression: NSRegularExpression
        let template: String
    }

    private static let rules: [RegexRule] = {
        let definitions: [(String, String)] = [
            // Authorization / cookie headers: consume the whole value (may contain spaces).
            (#"(?i)\b(?:authorization|proxy-authorization)\s*[:=][^\r\n]*"#, "<redacted-header>"),
            (#"(?i)\b(?:cookie|set-cookie)\s*[:=][^\r\n]*"#, "<redacted-header>"),
            // Common query/form key/value pairs. Keep the key so logs stay actionable.
            (#"(?i)\b(access_token|refresh_token|id_token|token|stoken|ltoken|cookie_token|login_ticket|account_id|game_uid|mid|uid|password|passwd|secret|sessionid|session_id|api_key|apikey|signature|sign)\s*=\s*[^&\s,;#]+"#,
             "$1=<redacted>"),
            (#"(?i)\bbearer\s+[A-Za-z0-9._~+/\-]+=*"#, "Bearer <redacted>"),
            (#"eyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}"#, "<redacted-jwt>"),
            (#"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#, "<redacted-email>"),
            (#"(?<![\w.])1[3-9]\d{9}(?![\w.])"#, "<redacted-phone>"),
            (#"(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b"#, "<redacted-id>"),
            // Conservative: long unbroken base64/hex-ish literals are almost always secrets.
            (#"(?<![A-Za-z0-9+/=_\-])[A-Za-z0-9+/=_\-]{32,}(?![A-Za-z0-9+/=_\-])"#, "<redacted-secret>")
        ]
        return definitions.compactMap { pattern, template in
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            return RegexRule(expression: regex, template: template)
        }
    }()

    private static let urlRegex = try! NSRegularExpression(
        pattern: #"https?://[^\s<>"'\)\]]+"#,
        options: [.caseInsensitive]
    )

    static func redact(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var value = redactURLs(in: text)
        for rule in rules {
            let range = NSRange(value.startIndex..., in: value)
            value = rule.expression.stringByReplacingMatches(
                in: value,
                options: [],
                range: range,
                withTemplate: rule.template
            )
        }
        return value
    }

    /// Reduces a URL to its origin. Never returns path, query or fragment.
    static func redactURL(_ url: URL) -> String {
        guard let scheme = url.scheme, let host = url.host else { return "<redacted-url>" }
        let port = url.port.map { ":\($0)" } ?? ""
        return "\(scheme)://\(host)\(port)"
    }

    /// Reduces a URL string to its origin, dropping credentials, path, query and fragment.
    static func redactURLString(_ raw: String) -> String {
        guard let url = URL(string: raw) else { return redact(raw) }
        return redactURL(url)
    }

    static func redact(metadata: [String: String]) -> [String: String] {
        var output: [String: String] = [:]
        // Bound the payload so a misbehaving page cannot flood an export. Keys are
        // developer-defined; values are always treated as untrusted.
        for (key, value) in metadata.prefix(16) {
            let safeKey = String(key.prefix(64))
            output[safeKey] = isSensitiveKey(key) ? replacement : String(redact(value).prefix(500))
        }
        return output
    }

    static func isSensitiveKey(_ key: String) -> Bool {
        let lowered = key.lowercased()
        return sensitiveKeyFragments.contains { lowered.contains($0) }
    }

    private static func redactURLs(in text: String) -> String {
        let matches = urlRegex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
        guard !matches.isEmpty else { return text }

        var result = text
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let raw = String(result[range])
            if let url = URL(string: raw) {
                result.replaceSubrange(range, with: redactURL(url))
            } else {
                result.replaceSubrange(range, with: "<redacted-url>")
            }
        }
        return result
    }
}
