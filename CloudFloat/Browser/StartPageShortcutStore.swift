import Foundation

/// A user-editable shortcut shown in the start page's "常用网站" grid.
struct StartPageShortcut: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var systemImage: String
    var urlString: String

    init(
        id: UUID = UUID(),
        title: String,
        systemImage: String,
        urlString: String
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.urlString = urlString
    }

    var url: URL? {
        URL(string: urlString)
    }

    var host: String {
        URL(string: urlString)?.host ?? urlString
    }
}

/// Curated SF Symbols offered by the shortcut editor. All are system symbols, so there are
/// no bundled images and no licensing surface.
enum ShortcutIconCatalog {
    static let options: [String] = [
        "globe",
        "magnifyingglass",
        "b.circle",
        "chevron.left.forwardslash.chevron.right",
        "cloud.fill",
        "gamecontroller.fill",
        "play.rectangle",
        "book.closed",
        "newspaper",
        "cart",
        "envelope",
        "bubble.left.and.bubble.right",
        "music.note",
        "film",
        "sportscourt",
        "graduationcap",
        "briefcase",
        "house",
        "star",
        "heart",
        "bolt",
        "map",
        "camera",
        "photo",
        "terminal",
        "display",
        "square.grid.2x2",
        "link",
        "safari",
        "sparkles"
    ]

    static let fallback = "globe"
}

/// Persists the start-page shortcuts. The three built-ins are only a seed; once the user
/// edits the list (including deleting everything), the stored list wins.
@MainActor
final class StartPageShortcutStore: ObservableObject {
    @Published private(set) var shortcuts: [StartPageShortcut]

    private let defaults: UserDefaults
    private let storageKey = "cf.shortcuts.v1"
    private let schemaKey = "cf.shortcuts.schema"
    private let currentSchema = 2

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([StartPageShortcut].self, from: data) {
            shortcuts = decoded
            migrateLegacySeedIfNeeded()
        } else {
            shortcuts = []
            persist()
        }
        defaults.set(currentSchema, forKey: schemaKey)
    }

    /// Builds 1–9 seeded a default list. The product now starts empty, so clear any list
    /// written before schema 2 once. After that, the user's list is authoritative.
    private func migrateLegacySeedIfNeeded() {
        guard defaults.integer(forKey: schemaKey) < currentSchema else { return }
        shortcuts = []
        persist()
    }
    @discardableResult
    func add(title: String, urlString: String, systemImage: String) -> StartPageShortcut? {
        guard let urlString = Self.normalizedURLString(urlString) else { return nil }
        let shortcut = StartPageShortcut(
            title: Self.normalizedTitle(title, fallback: URL(string: urlString)?.host ?? urlString),
            systemImage: systemImage.isEmpty ? ShortcutIconCatalog.fallback : systemImage,
            urlString: urlString
        )
        shortcuts.append(shortcut)
        persist()
        return shortcut
    }

    func update(
        id: UUID,
        title: String,
        urlString: String,
        systemImage: String
    ) -> Bool {
        guard let index = shortcuts.firstIndex(where: { $0.id == id }),
              let normalized = Self.normalizedURLString(urlString) else { return false }
        shortcuts[index].title = Self.normalizedTitle(
            title,
            fallback: URL(string: normalized)?.host ?? normalized
        )
        shortcuts[index].urlString = normalized
        shortcuts[index].systemImage = systemImage.isEmpty ? ShortcutIconCatalog.fallback : systemImage
        persist()
        return true
    }

    func remove(id: UUID) {
        shortcuts.removeAll { $0.id == id }
        persist()
    }

    func remove(at offsets: IndexSet) {
        shortcuts.remove(atOffsets: offsets)
        persist()
    }

    func move(from source: IndexSet, to destination: Int) {
        shortcuts.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(shortcuts) else { return }
        defaults.set(data, forKey: storageKey)
    }

    static func normalizedURLString(_ raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if !value.contains("://") {
            value = "https://" + value
        }
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host?.isEmpty == false else { return nil }
        return url.absoluteString
    }

    private static func normalizedTitle(_ raw: String, fallback: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
