import AVKit
import Combine
import Foundation

/// Owns Picture-in-Picture separately from the currently selected tab.
///
/// A PiP source is the tab whose media started PiP. Switching tabs must never rebind this
/// manager to another tab; closing a source tab is protected while PiP is active.
@MainActor
final class PiPManager: ObservableObject {
    @Published private(set) var activePiPTabID: UUID?
    @Published private(set) var coordinators: [UUID: WebPictureInPictureCoordinator] = [:]

    var onAnyChange: (() -> Void)?
    var onStateChanged: ((UUID, WebPictureInPictureCoordinator.State) -> Void)?
    var onOutcome: ((UUID, PiPRequestOutcome, PiPAvailability) -> Void)?

    private var observationCancellables: [UUID: AnyCancellable] = [:]
    private let now: () -> Date

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    func coordinator(for session: BrowserSession) -> WebPictureInPictureCoordinator {
        if let existing = coordinators[session.id] {
            return existing
        }
        let coordinator = WebPictureInPictureCoordinator(
            mediaDetector: session.mediaDetector,
            configurationAllowsPiP: { [weak session] in
                session?.pictureInPictureAllowedByConfiguration ?? false
            },
            now: now
        )
        coordinators[session.id] = coordinator
        observationCancellables[session.id] = coordinator.objectWillChange.sink { [weak self] _ in
            self?.onAnyChange?()
        }
        coordinator.onStateChanged = { [weak self, weak session] state in
            guard let self, let session else { return }
            if state == .active {
                activePiPTabID = session.id
            } else if activePiPTabID == session.id, state == .available {
                // A coordinator can briefly move to available while reconciling snapshots.
                // Only clear when an explicit leave event has been observed by AppCoordinator.
            }
            onStateChanged?(session.id, state)
        }
        coordinator.onOutcome = { [weak self, weak session] outcome, availability in
            guard let self, let session else { return }
            if case .success = outcome {
                activePiPTabID = session.id
            }
            onOutcome?(session.id, outcome, availability)
        }
        onAnyChange?()
        return coordinator
    }

    func coordinator(for tabID: UUID) -> WebPictureInPictureCoordinator? {
        coordinators[tabID]
    }

    var activePiPCoordinator: WebPictureInPictureCoordinator? {
        activePiPTabID.flatMap { coordinators[$0] }
    }

    func isPiPActive(for session: BrowserSession) -> Bool {
        activePiPTabID == session.id
    }

    func isPiPActive(for tabID: UUID) -> Bool {
        activePiPTabID == tabID
    }

    @discardableResult
    func requestPiP(for session: BrowserSession) async -> PiPRequestOutcome {
        let coordinator = self.coordinator(for: session)
        return await coordinator.requestPiP()
    }

    func exitPiP(for session: BrowserSession) {
        coordinator(for: session).exitPiP()
    }

    func exitActivePiP() {
        activePiPCoordinator?.exitPiP()
    }

    func handle(event: MediaPlaybackEvent, from session: BrowserSession) {
        // Route to the source tab even when another tab is selected.
        coordinator(for: session).handle(event: event)
    }

    func handle(aggregate: MediaAggregate, snapshot: MediaFrameSnapshot, from session: BrowserSession) {
        coordinator(for: session).handle(aggregate: aggregate, snapshotReceivedAt: snapshot.receivedAt)
    }

    func clearActivePiP(for session: BrowserSession) {
        guard activePiPTabID == session.id else { return }
        activePiPTabID = nil
        onAnyChange?()
    }

    func refreshAvailability(for session: BrowserSession) {
        coordinator(for: session).refreshAvailability()
    }

    /// Returns false when closing would destroy an active PiP source.
    func canCloseTab(_ session: BrowserSession) -> Bool {
        !isPiPActive(for: session)
    }

    func stopObserving(_ session: BrowserSession) {
        observationCancellables.removeValue(forKey: session.id)?.cancel()
        // Keep the coordinator alive if it is the active PiP source; otherwise release it.
        if activePiPTabID != session.id {
            coordinators.removeValue(forKey: session.id)
        }
        onAnyChange?()
    }
}
