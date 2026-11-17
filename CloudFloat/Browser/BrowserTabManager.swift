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

    private let navigationPolicy: NavigationPolicy
    private let inPageControlEnabled: Bool
    private let javaScriptCanOpenWindowsAutomatically: Bool
    private var sessionObservations: [UUID: AnyCancellable] = [:]

    var activeSession: BrowserSession {
        sessions.first { $0.id == activeSessionID } ?? sessions.last!
    }

    init(
        navigationPolicy: NavigationPolicy = NavigationPolicy(),
        inPageControlEnabled: Bool = true,
        javaScriptCanOpenWindowsAutomatically: Bool = true,
        recentlyClosed: RecentlyClosedStore? = nil
    ) {
        self.navigationPolicy = navigationPolicy
        self.inPageControlEnabled = inPageControlEnabled
        self.javaScriptCanOpenWindowsAutomatically = javaScriptCanOpenWindowsAutomatically
        self.recentlyClosed = recentlyClosed ?? RecentlyClosedStore()
        self.activeSessionID = UUID()
        let first = makeSession()
        sessions = [first]
        activeSessionID = first.id
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
        return session
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
                title: session.pageTitle,
                url: session.currentURL,
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
            injectedConfiguration: configuration
        )
        configure(session)
        onSessionCreated?(session)
        sessions.append(session)
        if activate {
            activeSessionID = session.id
        }
        onAnyChange?()
        return session
    }

    func activateNextTab() {
        guard sessions.count > 1, let index = activeSessionIndex else { return }
        let next = (index + 1) % sessions.count
        activeSessionID = sessions[next].id
        onAnyChange?()
    }

    func activatePreviousTab() {
        guard sessions.count > 1, let index = activeSessionIndex else { return }
        let previous = (index - 1 + sessions.count) % sessions.count
        activeSessionID = sessions[previous].id
        onAnyChange?()
    }

    func shutdown() {
        for session in sessions {
            session.tearDown()
        }
        sessions = []
        sessionObservations.removeAll()
    }

    private func makeSession(isPrivate: Bool = false) -> BrowserSession {
        let session = BrowserSession(
            navigationPolicy: navigationPolicy,
            inPageControlEnabled: inPageControlEnabled,
            javaScriptCanOpenWindowsAutomatically: javaScriptCanOpenWindowsAutomatically,
            websiteDataStore: isPrivate ? privateDataStore : .default(),
            isPrivate: isPrivate
        )
        configure(session)
        onSessionCreated?(session)
        return session
    }

    private func configure(_ session: BrowserSession) {
        session.onEvent = { [weak self, weak session] event in
            guard let self, let session else { return }
            self.onSessionEvent?(session, event)
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
