import Foundation

struct BookmarkFolder: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var sortOrder: Int
    var createdAt: Date
}

struct Bookmark: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var urlString: String
    var folderID: UUID
    var sortOrder: Int
    var createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        urlString: String,
        folderID: UUID? = nil,
        sortOrder: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.urlString = urlString
        self.folderID = folderID ?? UUID()
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }

    var url: URL? {
        URL(string: urlString)
    }
}

/// User-managed bookmarks with folders and explicit ordering. Ariuno does not seed or
/// hard-code any site, including cloud game pages.
@MainActor
final class BookmarkStore: ObservableObject {
    @Published private(set) var folders: [BookmarkFolder] = []
    @Published private(set) var bookmarks: [Bookmark] = []

    private let defaults: UserDefaults
    private let foldersKey: String
    private let bookmarksKey: String

    init(
        defaults: UserDefaults = .standard,
        foldersKey: String = "cf.bookmarkFolders.v1",
        bookmarksKey: String = "cf.bookmarks.v2"
    ) {
        self.defaults = defaults
        self.foldersKey = foldersKey
        self.bookmarksKey = bookmarksKey
        load()
        if folders.isEmpty {
            folders = [BookmarkFolder(id: UUID(), name: "书签", sortOrder: 0, createdAt: Date())]
            persistFolders()
        }
    }

    var rootFolder: BookmarkFolder? {
        folders.min { $0.sortOrder < $1.sortOrder }
    }

    func bookmarks(in folderID: UUID) -> [Bookmark] {
        bookmarks
            .filter { $0.folderID == folderID }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    func add(title: String, url: URL, folderID: UUID? = nil) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = trimmedTitle.isEmpty ? (url.host ?? url.absoluteString) : trimmedTitle
        let targetFolder = folderID ?? rootFolder?.id
        let order = (bookmarks.filter { $0.folderID == targetFolder }.map(\.sortOrder).max() ?? -1) + 1
        if let index = bookmarks.firstIndex(where: { $0.urlString == url.absoluteString }) {
            bookmarks[index].title = resolvedTitle
            bookmarks[index].folderID = targetFolder ?? rootFolder!.id
        } else {
            bookmarks.append(
                Bookmark(
                    title: resolvedTitle,
                    urlString: url.absoluteString,
                    folderID: targetFolder ?? rootFolder!.id,
                    sortOrder: order
                )
            )
        }
        persistBookmarks()
    }

    func update(_ bookmark: Bookmark) {
        guard let index = bookmarks.firstIndex(where: { $0.id == bookmark.id }) else { return }
        bookmarks[index] = bookmark
        persistBookmarks()
    }

    func remove(_ id: UUID) {
        bookmarks.removeAll { $0.id == id }
        persistBookmarks()
    }

    /// Batch delete from a stable ID snapshot; persists once.
    func remove(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        bookmarks.removeAll { ids.contains($0.id) }
        persistBookmarks()
    }

    func move(_ id: UUID, to folderID: UUID) {
        guard let index = bookmarks.firstIndex(where: { $0.id == id }) else { return }
        let order = (bookmarks.filter { $0.folderID == folderID }.map(\.sortOrder).max() ?? -1) + 1
        bookmarks[index].folderID = folderID
        bookmarks[index].sortOrder = order
        persistBookmarks()
    }

    func sortBookmarks(in folderID: UUID, by order: BookmarkSortOrder) {
        let indexes = bookmarks
            .enumerated()
            .filter { $0.element.folderID == folderID }
            .map(\.offset)
        guard indexes.count > 1 else { return }
        let sortedIndexes = indexes.sorted { lhs, rhs in
            let lhsItem = bookmarks[lhs]
            let rhsItem = bookmarks[rhs]
            switch order {
            case .title: return lhsItem.title.localizedCaseInsensitiveCompare(rhsItem.title) == .orderedAscending
            case .url: return lhsItem.urlString < rhsItem.urlString
            case .newest: return lhsItem.createdAt > rhsItem.createdAt
            }
        }
        for (position, originalIndex) in sortedIndexes.enumerated() {
            bookmarks[originalIndex].sortOrder = position
        }
        persistBookmarks()
    }

    func createFolder(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let order = (folders.map(\.sortOrder).max() ?? -1) + 1
        folders.append(BookmarkFolder(id: UUID(), name: trimmed, sortOrder: order, createdAt: Date()))
        persistFolders()
    }

    func renameFolder(_ id: UUID, to name: String) {
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        folders[index].name = trimmed
        persistFolders()
    }

    func removeFolder(_ id: UUID) {
        guard folders.count > 1, let root = rootFolder, root.id != id else { return }
        var order = (bookmarks.filter { $0.folderID == root.id }.map(\.sortOrder).max() ?? -1) + 1
        for index in bookmarks.indices where bookmarks[index].folderID == id {
            bookmarks[index].folderID = root.id
            bookmarks[index].sortOrder = order
            order += 1
        }
        folders.removeAll { $0.id == id }
        persistFolders()
        persistBookmarks()
    }

    func isBookmarked(_ url: URL) -> Bool {
        bookmarks.contains { $0.urlString == url.absoluteString }
    }

    private func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let folderData = defaults.data(forKey: foldersKey) {
            folders = (try? decoder.decode([BookmarkFolder].self, from: folderData)) ?? []
        }
        if let bookmarkData = defaults.data(forKey: bookmarksKey) {
            bookmarks = (try? decoder.decode([Bookmark].self, from: bookmarkData)) ?? []
        }
    }

    private func persistFolders() {
        persist(folders, to: foldersKey)
    }

    private func persistBookmarks() {
        persist(bookmarks, to: bookmarksKey)
    }

    private func persist<T: Encodable>(_ value: T, to key: String) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        if let data = try? encoder.encode(value) {
            defaults.set(data, forKey: key)
        }
    }
}

enum BookmarkSortOrder: String, CaseIterable, Identifiable {
    case title
    case url
    case newest

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .title: return "按名称"
        case .url: return "按网址"
        case .newest: return "按添加时间"
        }
    }
}
