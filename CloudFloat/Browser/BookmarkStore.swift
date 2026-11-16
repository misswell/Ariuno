import Foundation

struct Bookmark: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var urlString: String
    var createdAt: Date

    init(id: UUID = UUID(), title: String, urlString: String, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.urlString = urlString
        self.createdAt = createdAt
    }

    var url: URL? {
        URL(string: urlString)
    }
}

/// User-managed bookmarks. CloudFloat does not seed or hard-code any site, including cloud
/// game pages; bookmarks are created by the user.
@MainActor
final class BookmarkStore: ObservableObject {
    @Published private(set) var bookmarks: [Bookmark] = []

    private let defaults: UserDefaults
    private let storageKey: String

    init(defaults: UserDefaults = .standard, storageKey: String = "cf.bookmarks.v1") {
        self.defaults = defaults
        self.storageKey = storageKey
        load()
    }

    func add(title: String, url: URL) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmedTitle.isEmpty ? (url.host ?? url.absoluteString) : trimmedTitle
        // Keep one entry per canonical URL string; updating an existing bookmark is friendlier
        // than accumulating duplicates when the user bookmarks the same page twice.
        if let index = bookmarks.firstIndex(where: { $0.urlString == url.absoluteString }) {
            bookmarks[index].title = title
        } else {
            bookmarks.append(Bookmark(title: title, urlString: url.absoluteString))
        }
        persist()
    }

    func update(_ bookmark: Bookmark) {
        guard let index = bookmarks.firstIndex(where: { $0.id == bookmark.id }) else { return }
        bookmarks[index] = bookmark
        persist()
    }

    func remove(_ id: UUID) {
        bookmarks.removeAll { $0.id == id }
        persist()
    }

    func bookmark(for url: URL) -> Bookmark? {
        bookmarks.first { $0.urlString == url.absoluteString }
    }

    func isBookmarked(_ url: URL) -> Bool {
        bookmark(for: url) != nil
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            bookmarks = try decoder.decode([Bookmark].self, from: data)
        } catch {
            bookmarks = []
        }
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(bookmarks) {
            defaults.set(data, forKey: storageKey)
        }
    }
}
