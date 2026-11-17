import Foundation

struct HistoryEntry: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var urlString: String
    var visitedAt: Date

    var url: URL? {
        URL(string: urlString)
    }
}

/// Persistent browsing history for normal tabs. Private tabs never enter this store.
/// Entries are capped and persisted with atomic replacement.
@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var entries: [HistoryEntry] = []

    private let fileURL: URL
    private let limit: Int

    init(fileURL: URL? = nil, limit: Int = 5_000) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let directory = (support ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("Ariuno", isDirectory: true)
        self.fileURL = fileURL ?? directory.appendingPathComponent("history-v1.json")
        self.limit = limit
        load()
    }

    func record(title: String, url: URL, visitedAt: Date = Date()) {
        guard url.absoluteString != "about:blank", url.scheme?.lowercased() != "file" else { return }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = HistoryEntry(
            id: UUID(),
            title: trimmedTitle.isEmpty ? (url.host ?? url.absoluteString) : trimmedTitle,
            urlString: url.absoluteString,
            visitedAt: visitedAt
        )
        // Collapse repeated reloads/same-document records into one recent entry.
        if let first = entries.first,
           first.urlString == entry.urlString,
           abs(first.visitedAt.timeIntervalSince(entry.visitedAt)) < 2 {
            return
        }
        entries.insert(entry, at: 0)
        if entries.count > limit {
            entries.removeLast(entries.count - limit)
        }
        persistAsync()
    }

    func entries(matching query: String) -> [HistoryEntry] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return entries }
        return entries.filter {
            $0.title.lowercased().contains(query) || $0.urlString.lowercased().contains(query)
        }
    }

    func remove(_ id: UUID) {
        entries.removeAll { $0.id == id }
        persistAsync()
    }

    func clear() {
        entries.removeAll()
        persistAsync()
    }

    private func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let data = try Data(contentsOf: fileURL)
            entries = try decoder.decode([HistoryEntry].self, from: data)
        } catch {
            entries = []
        }
    }

    private func persistAsync() {
        let entries = self.entries
        let url = fileURL
        Task.detached(priority: .utility) {
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(entries) {
                try? data.write(to: url, options: [.atomic])
            }
        }
    }
}

/// Groups user library stores. Bookmarks, history, and recently closed tabs are independent
/// so their persistence and lifecycle can evolve separately.
@MainActor
final class BrowserLibraryStore: ObservableObject {
    let bookmarks: BookmarkStore
    let history: HistoryStore
    let recentlyClosed: RecentlyClosedStore

    init(
        bookmarks: BookmarkStore? = nil,
        history: HistoryStore? = nil,
        recentlyClosed: RecentlyClosedStore? = nil
    ) {
        self.bookmarks = bookmarks ?? BookmarkStore()
        self.history = history ?? HistoryStore()
        self.recentlyClosed = recentlyClosed ?? RecentlyClosedStore()
    }
}
