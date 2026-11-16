import Combine
import Foundation

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

    private let navigationPolicy: NavigationPolicy
    private let inPageControlEnabled: Bool
    private var sessionObservations: [UUID: AnyCancellable] = [:]

    var activeSession: BrowserSession {
        sessions.first { $0.id == activeSessionID } ?? sessions.last!
    }

    init(
        navigationPolicy: NavigationPolicy = NavigationPolicy(),
        inPageControlEnabled: Bool = true
    ) {
        self.navigationPolicy = navigationPolicy
        self.inPageControlEnabled = inPageControlEnabled
        self.activeSessionID = UUID()
        let first = makeSession()
        sessions = [first]
        activeSessionID = first.id
    }

    var activeSessionIndex: Int? {
        sessions.firstIndex { $0.id == activeSessionID }
    }

    @discardableResult
    func createTab(url: URL? = nil, activate: Bool = true) -> BrowserSession {
        let session = makeSession()
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

    func closeTab(_ session: BrowserSession) {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
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
    }

    func activateTab(_ session: BrowserSession) {
        guard sessions.contains(where: { $0.id == session.id }) else { return }
        activeSessionID = session.id
        onAnyChange?()
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

    private func makeSession() -> BrowserSession {
        let session = BrowserSession(
            navigationPolicy: navigationPolicy,
            inPageControlEnabled: inPageControlEnabled
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
        sessionObservations[session.id] = session.objectWillChange.sink { [weak self] _ in
            self?.onAnyChange?()
        }
    }
}
