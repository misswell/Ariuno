import Foundation
import WebKit

/// Read-only view of WebKit's persistent website data. Only domain-level records are
/// counted; cookie names, values and HttpOnly tokens are never read or surfaced.
@MainActor
final class CookieStore: NSObject, ObservableObject {
    @Published private(set) var cookieRecordCount: Int = 0
    @Published private(set) var officialSiteRecordCount: Int = 0
    @Published private(set) var isClearing: Bool = false
    @Published private(set) var lastClearedAt: Date?

    var onChange: ((Int) -> Void)?

    private let dataStore: WKWebsiteDataStore
    private let now: () -> Date
    private var observing = false

    private static let officialDomainSuffixes = ["mihoyo.com", "hoyoverse.com", "hoyolab.com"]

    init(dataStore: WKWebsiteDataStore, now: @escaping () -> Date = Date.init) {
        self.dataStore = dataStore
        self.now = now
        super.init()
    }

    func start() {
        guard !observing else { return }
        dataStore.httpCookieStore.add(self)
        observing = true
        refresh()
    }

    func stop() {
        guard observing else { return }
        dataStore.httpCookieStore.remove(self)
        observing = false
    }

    func refresh() {
        // `dataRecords` exposes only domain-level records; unlike `allCookies` it does not
        // load HttpOnly cookie values into app memory.
        Task { @MainActor [weak self] in
            guard let self else { return }
            let records = await self.dataStore.dataRecords(ofTypes: [WKWebsiteDataTypeCookies])
            let total = records.count
            let official = records.filter { record in
                let domain = record.displayName
                    .lowercased()
                    .trimmingCharacters(in: CharacterSet(charactersIn: "."))
                return Self.officialDomainSuffixes.contains { suffix in
                    domain == suffix || domain.hasSuffix("." + suffix)
                }
            }.count
            let changed = self.cookieRecordCount != total
            self.cookieRecordCount = total
            self.officialSiteRecordCount = official
            if changed {
                self.onChange?(total)
            }
        }
    }

    /// Removes all WebKit website data (cookies, local storage, caches, IndexedDB, ...).
    /// Only call after an explicit user confirmation.
    func clearAll() async -> Result<Void, Error> {
        isClearing = true
        defer { isClearing = false }
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        let result: Result<Void, Error> = await withCheckedContinuation { continuation in
            dataStore.removeData(ofTypes: dataTypes, modifiedSince: .distantPast) {
                continuation.resume(returning: .success(()))
            }
        }
        if case .success = result {
            lastClearedAt = now()
            refresh()
        }
        return result
    }

    /// Best-effort check without reading cookie values. It cannot prove login state.
    var hasOfficialSiteCookieRecords: Bool {
        officialSiteRecordCount > 0
    }
}

extension CookieStore: WKHTTPCookieStoreObserver {
    nonisolated func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        Task { @MainActor [weak self] in
            self?.refresh()
        }
    }
}
