import Foundation
import SwiftUI

/// A compact address-bar autocomplete item. History and bookmarks are the only sources;
/// nothing is fetched from a search engine or a remote suggestion service.
struct AddressSuggestion: Identifiable, Equatable {
    enum Kind: Equatable {
        case history
        case bookmark
    }

    let id: String
    let title: String
    let urlString: String
    let kind: Kind

    var displayTitle: String {
        if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return title
        }
        return URL(string: urlString)?.host ?? urlString
    }

    var displayHost: String {
        URL(string: urlString)?.host ?? urlString
    }
}

@MainActor
enum AddressSuggestionProvider {
    /// Matches history titles/URLs and bookmarks, bookmarks first, newest history first.
    /// The result is deduplicated by URL and capped so the keyboard stays usable.
    static func suggestions(
        query: String,
        history: [HistoryEntry],
        bookmarks: [Bookmark],
        limit: Int = 5
    ) -> [AddressSuggestion] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let needle = trimmed.lowercased()

        func matches(title: String, urlString: String) -> Bool {
            title.lowercased().contains(needle) || urlString.lowercased().contains(needle)
        }

        var results: [AddressSuggestion] = []
        var seenURLs = Set<String>()

        for bookmark in bookmarks {
            guard bookmark.url != nil,
                  matches(title: bookmark.title, urlString: bookmark.urlString),
                  seenURLs.insert(bookmark.urlString).inserted else { continue }
            results.append(
                AddressSuggestion(
                    id: bookmark.urlString,
                    title: bookmark.title,
                    urlString: bookmark.urlString,
                    kind: .bookmark
                )
            )
            if results.count >= limit { return results }
        }

        for entry in history {
            guard entry.url != nil,
                  matches(title: entry.title, urlString: entry.urlString),
                  seenURLs.insert(entry.urlString).inserted else { continue }
            results.append(
                AddressSuggestion(
                    id: entry.urlString,
                    title: entry.title,
                    urlString: entry.urlString,
                    kind: .history
                )
            )
            if results.count >= limit { return results }
        }

        return results
    }
}

/// One tappable suggestion row. Used by both the start page and browser chrome.
struct AddressSuggestionRow: View {
    let suggestion: AddressSuggestion

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: suggestion.kind == .bookmark ? "bookmark.fill" : "clock")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.displayTitle)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(suggestion.displayHost)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "arrow.up.left")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }
}
