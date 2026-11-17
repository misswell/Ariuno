import Foundation

enum SearchEngine: String, Codable, CaseIterable, Identifiable {
    case google
    case bing
    case duckduckgo

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .google: return "Google"
        case .bing: return "Bing"
        case .duckduckgo: return "DuckDuckGo"
        }
    }

    func searchURL(for query: String) -> URL? {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        switch self {
        case .google: return URL(string: "https://www.google.com/search?q=\(encoded)")
        case .bing: return URL(string: "https://www.bing.com/search?q=\(encoded)")
        case .duckduckgo: return URL(string: "https://duckduckgo.com/?q=\(encoded)")
        }
    }
}
