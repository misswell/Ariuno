import Foundation

struct ClosedTabSnapshot: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var urlString: String
    var closedAt: Date

    var url: URL? {
        URL(string: urlString)
    }
}

/// Stores recently closed normal tabs. Private tabs are intentionally excluded.
@MainActor
final class RecentlyClosedStore: ObservableObject {
    @Published private(set) var snapshots: [ClosedTabSnapshot] = []

    private let storageKey = "cf.recentlyClosedTabs.v1"
    private let defaults: UserDefaults
    private let limit = 20

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func record(title: String, url: URL?, closedAt: Date) {
        guard let url, url.absoluteString != "about:blank" else { return }
        let snapshot = ClosedTabSnapshot(
            id: UUID(),
            title: title.isEmpty ? (url.host ?? "未命名页面") : title,
            urlString: url.absoluteString,
            closedAt: closedAt
        )
        snapshots.insert(snapshot, at: 0)
        if snapshots.count > limit {
            snapshots.removeLast(snapshots.count - limit)
        }
        persist()
    }

    func restoreLast() -> ClosedTabSnapshot? {
        guard !snapshots.isEmpty else { return nil }
        let snapshot = snapshots.removeFirst()
        persist()
        return snapshot
    }

    func remove(_ id: UUID) {
        snapshots.removeAll { $0.id == id }
        persist()
    }

    func clear() {
        snapshots.removeAll()
        persist()
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        snapshots = (try? decoder.decode([ClosedTabSnapshot].self, from: data)) ?? []
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(snapshots) {
            defaults.set(data, forKey: storageKey)
        }
    }
}
