import Foundation

/// Minimal metadata for a tab that survives a cold start. Only URLs/titles/timestamps are
/// persisted: WKWebView objects are never serialised, and private tabs are never written.
struct PersistedTab: Codable, Identifiable, Equatable {
    let id: UUID
    var urlString: String
    var title: String
    var lastVisitedAt: Date
}

struct PersistedBrowserState: Codable, Equatable {
    var version: Int
    var tabs: [PersistedTab]
    var activeTabID: UUID?
    var updatedAt: Date

    static let currentVersion = 1

    static var empty: PersistedBrowserState {
        PersistedBrowserState(version: currentVersion, tabs: [], activeTabID: nil, updatedAt: Date())
    }
}

/// Versioned, atomically replaced JSON persistence for tab metadata. Writes are debounced so
/// title/progress churn during page loads does not hammer the disk; `flush()` forces a write
/// (used when the app backgrounds and by tests).
@MainActor
final class TabSessionStore: ObservableObject {
    private let fileURL: URL
    private let maxTabs: Int
    private var pendingState: PersistedBrowserState?
    private var pendingTask: Task<Void, Never>?
    private let debounceNanoseconds: UInt64

    init(
        fileURL: URL? = nil,
        maxTabs: Int = 20,
        debounce: TimeInterval = 0.4
    ) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let directory = (support ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("Ariuno", isDirectory: true)
        self.fileURL = fileURL ?? directory.appendingPathComponent("tabs-v1.json")
        self.maxTabs = maxTabs
        self.debounceNanoseconds = UInt64(max(0, debounce) * 1_000_000_000)
    }

    var storageURL: URL { fileURL }

    func load() -> PersistedBrowserState {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: fileURL),
              let state = try? decoder.decode(PersistedBrowserState.self, from: data),
              state.version == PersistedBrowserState.currentVersion else {
            return .empty
        }
        return PersistedBrowserState(
            version: state.version,
            tabs: Array(state.tabs.prefix(maxTabs)),
            activeTabID: state.activeTabID,
            updatedAt: state.updatedAt
        )
    }

    func scheduleSave(_ state: PersistedBrowserState) {
        pendingState = normalised(state)
        pendingTask?.cancel()
        let delay = debounceNanoseconds
        pendingTask = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            }
            guard !Task.isCancelled else { return }
            self?.writePending()
        }
    }

    /// Writes any pending state immediately. Safe to call on background transitions.
    func flush() {
        pendingTask?.cancel()
        pendingTask = nil
        writePending()
    }

    func clear() {
        pendingTask?.cancel()
        pendingTask = nil
        pendingState = nil
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func normalised(_ state: PersistedBrowserState) -> PersistedBrowserState {
        var seen = Set<UUID>()
        let tabs = state.tabs.filter { tab in
            guard seen.insert(tab.id).inserted else { return false }
            let trimmed = tab.urlString.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty && trimmed != "about:blank"
        }
        let limited = Array(tabs.prefix(maxTabs))
        let active = state.activeTabID.flatMap { id in
            limited.contains(where: { $0.id == id }) ? id : nil
        }
        return PersistedBrowserState(
            version: PersistedBrowserState.currentVersion,
            tabs: limited,
            activeTabID: active,
            updatedAt: Date()
        )
    }

    private func writePending() {
        guard let state = pendingState else { return }
        pendingState = nil
        let url = fileURL
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(state)
            try data.write(to: url, options: [.atomic])
        } catch {
            // Tab restoration is a convenience; a failed write must never break browsing.
        }
    }
}
