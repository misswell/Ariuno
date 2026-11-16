import Foundation

/// Turns free-form address-bar text into a URL without hard-coding any destination.
enum URLInputParser {
    static func url(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.lowercased() != "about:blank" else { return nil }

        if let url = URL(string: trimmed) {
            if isAllowedScheme(url.scheme) {
                return normalized(url)
            }
            // Explicit non-web schemes must never be silently rewritten into HTTPS.
            if url.scheme?.lowercased().contains("://") == true || trimmed.lowercased().contains("://") {
                return nil
            }
        }

        // Treat host-like input as HTTPS. This keeps the address bar useful without tying the
        // browser to any specific site or search backend.
        if looksLikeHostOrURL(trimmed), let url = URL(string: "https://\(trimmed)") {
            return normalized(url)
        }
        return nil
    }

    static func placeholderURL() -> URL {
        URL(string: "about:blank")!
    }

    private static func normalized(_ url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        if components.scheme?.lowercased() == "http", components.host == "localhost" || components.host == "127.0.0.1" {
            // Local test servers are allowed by NavigationPolicy, but keeping the scheme intact
            // here avoids surprising scheme rewrites during development.
            components.scheme = "http"
        }
        return components.url
    }

    private static func isAllowedScheme(_ scheme: String?) -> Bool {
        guard let scheme = scheme?.lowercased() else { return false }
        return ["http", "https", "file", "about"].contains(scheme)
    }

    private static func looksLikeHostOrURL(_ text: String) -> Bool {
        guard !text.contains(" "), !text.contains("\n"), !text.contains("\t") else { return false }
        if text.lowercased().hasPrefix("localhost") {
            return true
        }
        let hostPart = text.split(separator: "/").first.map(String.init) ?? text
        return hostPart.contains(".")
            || hostPart.contains(":")
            || hostPart.lowercased().hasSuffix(".local")
    }
}
