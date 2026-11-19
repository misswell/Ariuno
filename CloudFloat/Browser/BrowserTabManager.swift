import Combine
import Foundation
import WebKit

/// Owns the open browser tabs. Each tab is an independent `BrowserSession` so cookies and
/// login state are shared by WebKit, while page state, media probing, and PiP stay isolated.
@MainActor
final class BrowserTabManager: ObservableObject {
    @Published private(set) var sessions: [BrowserSession] = []
    @Published private(set) var activeSessionID: UUID

    var onSessionEvent: ((BrowserSession, BrowserEvent) -> Void)?
    var onMediaSnapshot: ((BrowserSession, MediaAggregate, MediaFrameSnapshot) -> Void)?
    var onMediaEvent: ((BrowserSession, MediaPlaybackEvent) -> Void)?
    var onProbeError: ((BrowserSession, String) -> Void)?
    var onSessionCreated: ((BrowserSession) -> Void)?
    var onAnyChange: (() -> Void)?
    var pipProtection: ((BrowserSession) -> Bool)?

    let privateDataStore = WKWebsiteDataStore.nonPersistent()
    let recentlyClosed: RecentlyClosedStore
    let persistence: TabSessionStore?
    /// One shared queue for all tabs, so switching/closing tabs never hides a download.
    let downloadManager = DownloadManager()

    private let navigationPolicy: NavigationPolicy
    private let inPageControlEnabled: Bool
    private let javaScriptCanOpenWindowsAutomatically: Bool
    private var desktopModeEnabled: Bool
    private var desktopViewportWidth: Int
    private var sessionObservations: [UUID: AnyCancellable] = [:]

    var activeSession: BrowserSession {
        sessions.first { $0.id == activeSessionID } ?? sessions.last!
    }

    init(
        navigationPolicy: NavigationPolicy = NavigationPolicy(),
        inPageControlEnabled: Bool = true,
        javaScriptCanOpenWindowsAutomatically: Bool = true,
        desktopModeEnabled: Bool = false,
        desktopViewportWidth: Int = 1280,
        recentlyClosed: RecentlyClosedStore? = nil,
        persistence: TabSessionStore? = nil,
        restorePersistedTabs: Bool = true
    ) {
        self.navigationPolicy = navigationPolicy
        self.inPageControlEnabled = inPageControlEnabled
        self.javaScriptCanOpenWindowsAutomatically = javaScriptCanOpenWindowsAutomatically
        self.desktopModeEnabled = desktopModeEnabled
        self.desktopViewportWidth = min(max(desktopViewportWidth, 800), 1920)
        self.recentlyClosed = recentlyClosed ?? RecentlyClosedStore()
        self.persistence = persistence
        self.activeSessionID = UUID()
        let first = makeSession()
        sessions = [first]
        activeSessionID = first.id
        if restorePersistedTabs, persistence != nil {
            restoreTabsFromDisk()
        }
    }

    /// Cold-start restoration. Tabs are recreated with metadata only; each page loads when the
    /// user first activates that tab (see `resumeRestoredPageIfNeeded`).
    private func restoreTabsFromDisk() {
        guard let persistence else { return }
        let state = persistence.load()
        guard !state.tabs.isEmpty else { return }
        var restored: [BrowserSession] = []
        for persisted in state.tabs {
            guard let url = URL(string: persisted.urlString),
                  url.absoluteString != "about:blank" else { continue }
            let session = makeSession(isPrivate: false, id: persisted.id)
            session.applyRestoredMetadata(
                url: url,
                title: persisted.title,
                lastVisitedAt: persisted.lastVisitedAt
            )
            restored.append(session)
        }
        guard !restored.isEmpty else { return }
        // Replace the initial blank tab with the restored set.
        sessions.forEach { $0.tearDown() }
        sessions = restored
        if let activeTabID = state.activeTabID,
           restored.contains(where: { $0.id == activeTabID }) {
            activeSessionID = activeTabID
        } else {
            activeSessionID = restored[restored.count - 1].id
        }
        onAnyChange?()
    }

    var activeSessionIndex: Int? {
        sessions.firstIndex { $0.id == activeSessionID }
    }

    @discardableResult
    func createTab(
        url: URL? = nil,
        isPrivate: Bool = false,
        activate: Bool = true
    ) -> BrowserSession {
        let session = makeSession(isPrivate: isPrivate)
        sessions.append(session)
        if activate {
            activeSessionID = session.id
        }
        if let url {
            session.loadURL(url)
        }
        onAnyChange?()
        schedulePersist()
        return session
    }

    /// Applies desktop mode to every open tab. Only the active page reloads immediately;
    /// background tabs pick it up on their next navigation.
    func applyDesktopMode(enabled: Bool, viewportWidth: Int, reloadActive: Bool) {
        desktopModeEnabled = enabled
        desktopViewportWidth = min(max(viewportWidth, 800), 1920)
        for session in sessions {
            session.applyDesktopMode(
                enabled: enabled,
                viewportWidth: desktopViewportWidth,
                reload: false
            )
        }
        if reloadActive {
            activeSession.reload()
        }
    }

    func session(withID id: UUID) -> BrowserSession? {
        sessions.first { $0.id == id }
    }

    enum TabCloseOutcome {
        case closed
        case requiresPiPConfirmation
    }

    @discardableResult
    func closeTab(_ session: BrowserSession, force: Bool = false) -> TabCloseOutcome {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return .closed }
        guard force || !isPiPProtected(session) else { return .requiresPiPConfirmation }

        if !session.isPrivate {
            recentlyClosed.record(
                title: session.displayTitle,
                url: session.displayURL,
                closedAt: Date()
            )
        }
        let wasActive = session.id == activeSessionID
        sessions.remove(at: index)
        sessionObservations.removeValue(forKey: session.id)?.cancel()
        session.tearDown()

        if sessions.isEmpty {
            let replacement = makeSession()
            sessions = [replacement]
            activeSessionID = replacement.id
        } else if wasActive {
            let nextIndex = min(index, sessions.count - 1)
            activeSessionID = sessions[nextIndex].id
        }
        onAnyChange?()
        schedulePersist()
        return .closed
    }

    /// Batch close takes a stable ID snapshot first, so removing tabs cannot shift indices
    /// while the caller is still iterating (the classic IndexSet crash).
    @discardableResult
    func closeTabs(withIDs ids: [UUID], force: Bool = false) -> TabCloseOutcome {
        let snapshot = ids.compactMap { session(withID: $0) }
        if !force, snapshot.contains(where: { isPiPProtected($0) }) {
            return .requiresPiPConfirmation
        }
        for session in snapshot {
            closeTab(session, force: force)
        }
        return .closed
    }

    func closeAllTabs(except session: BrowserSession? = nil, force: Bool = false) -> Bool {
        let victims = sessions.filter { $0.id != session?.id }
        let blocked = victims.contains { !force && isPiPProtected($0) }
        guard !blocked else { return false }
        for session in victims {
            closeTab(session, force: true)
        }
        return true
    }

    func restoreRecentlyClosed() -> ClosedTabSnapshot? {
        guard let snapshot = recentlyClosed.restoreLast() else { return nil }
        createTab(url: snapshot.url, isPrivate: false)
        return snapshot
    }

    func clearRecentlyClosed() {
        recentlyClosed.clear()
    }

    private func isPiPProtected(_ session: BrowserSession) -> Bool {
        pipProtection?(session) ?? false
    }

    func activateTab(_ session: BrowserSession) {
        guard sessions.contains(where: { $0.id == session.id }) else { return }
        activeSessionID = session.id
        onAnyChange?()
        schedulePersist()
    }

    func createTabWithInjectedConfiguration(
        configuration: WKWebViewConfiguration,
        isPrivate: Bool,
        activate: Bool = true
    ) -> BrowserSession {
        let session = BrowserSession(
            navigationPolicy: navigationPolicy,
            inPageControlEnabled: inPageControlEnabled,
            javaScriptCanOpenWindowsAutomatically: javaScriptCanOpenWindowsAutomatically,
            isPrivate: isPrivate,
            injectedConfiguration: configuration,
            downloadManager: downloadManager,
            desktopModeEnabled: desktopModeEnabled,
            desktopViewportWidth: desktopViewportWidth
        )
        configure(session)
        onSessionCreated?(session)
        sessions.append(session)
        if activate {
            activeSessionID = session.id
        }
        onAnyChange?()
        schedulePersist()
        return session
    }

    func activateNextTab() {
        guard sessions.count > 1, let index = activeSessionIndex else { return }
        let next = (index + 1) % sessions.count
        activeSessionID = sessions[next].id
        onAnyChange?()
        schedulePersist()
    }

    func activatePreviousTab() {
        guard sessions.count > 1, let index = activeSessionIndex else { return }
        let previous = (index - 1 + sessions.count) % sessions.count
        activeSessionID = sessions[previous].id
        onAnyChange?()
        schedulePersist()
    }

    // MARK: - Persistence

    /// Persists non-private tabs with a real URL plus the active tab id. Private sessions are
    /// never written; a browser with only private/blank tabs persists an empty tab list.
    func persistState() {
        guard let persistence else { return }
        let persistable = sessions.filter {
            !$0.isPrivate && !$0.isClosed
                && ($0.displayURL?.absoluteString.isEmpty == false)
                && $0.displayURL?.absoluteString != "about:blank"
        }
        let tabs = persistable.map { session in
            PersistedTab(
                id: session.id,
                urlString: session.displayURL?.absoluteString ?? "",
                title: session.displayTitle,
                lastVisitedAt: session.lastVisitedAt
            )
        }
        let activeID = persistable.contains(where: { $0.id == activeSessionID })
            ? activeSessionID
            : persistable.first?.id
        persistence.scheduleSave(
            PersistedBrowserState(
                version: PersistedBrowserState.currentVersion,
                tabs: tabs,
                activeTabID: activeID,
                updatedAt: Date()
            )
        )
    }

    func promptPersist() {
        schedulePersist()
    }

    func savePersistedStateNow() {
        persistState()
        persistence?.flush()
    }

    private func schedulePersist() {
        guard persistence != nil else { return }
        persistState()
    }

    func shutdown() {
        for session in sessions {
            session.tearDown()
        }
        sessions = []
        sessionObservations.removeAll()
    }

    private func makeSession(isPrivate: Bool = false, id: UUID = UUID()) -> BrowserSession {
        // Normal tabs MUST use .default(). It is the persistent store that keeps cookies,
        // localStorage, IndexedDB and the HTTP cache across app launches and App Store
        // updates. Only private tabs use the shared non-persistent store. Never clear this
        // store at launch and never uninstall the app when installing a new build.
        let session = BrowserSession(
            id: id,
            navigationPolicy: navigationPolicy,
            inPageControlEnabled: inPageControlEnabled,
            javaScriptCanOpenWindowsAutomatically: javaScriptCanOpenWindowsAutomatically,
            websiteDataStore: isPrivate ? privateDataStore : .default(),
            isPrivate: isPrivate,
            downloadManager: downloadManager,
            desktopModeEnabled: desktopModeEnabled,
            desktopViewportWidth: desktopViewportWidth
        )
        configure(session)
        onSessionCreated?(session)
        return session
    }

    private func configure(_ session: BrowserSession) {
        session.onEvent = { [weak self, weak session] event in
            guard let self, let session else { return }
            self.onSessionEvent?(session, event)
            switch event {
            case .titleChanged, .loadFinished, .navigationCommitted, .webContentProcessTerminated:
                self.schedulePersist()
            default:
                break
            }
        }
        session.mediaDetector.onSnapshot = { [weak self, weak session] aggregate, snapshot in
            guard let self, let session else { return }
            self.onMediaSnapshot?(session, aggregate, snapshot)
        }
        session.mediaDetector.onEvent = { [weak self, weak session] event in
            guard let self, let session else { return }
            self.onMediaEvent?(session, event)
        }
        session.mediaDetector.onProbeError = { [weak self, weak session] message in
            guard let self, let session else { return }
            self.onProbeError?(session, message)
        }
        session.onAnyChange = { [weak self] in
            self?.onAnyChange?()
        }
        session.onCreateWindow = { [weak self, weak session] configuration, action in
            guard let self, let session else { return nil }
            // WebKit requires the returned WKWebView to be created with the supplied
            // configuration. Give the new tab its own user content controller so media probe
            // handlers do not collide with the source tab.
            configuration.userContentController = WKUserContentController()
            let newSession = self.createTabWithInjectedConfiguration(
                configuration: configuration,
                isPrivate: session.isPrivate
            )
            return newSession.webView
        }
        session.onCloseWindow = { [weak self, weak session] closedSession in
            guard let self, let session else { return }
            self.closeTab(session, force: false)
        }
        sessionObservations[session.id] = session.objectWillChange.sink { [weak self] _ in
            self?.onAnyChange?()
        }
        recentlyClosed.objectWillChange.sink { [weak self] _ in
            self?.onAnyChange?()
        }.store(in: &changeCancellables)
    }

    private var changeCancellables = Set<AnyCancellable>()
}
