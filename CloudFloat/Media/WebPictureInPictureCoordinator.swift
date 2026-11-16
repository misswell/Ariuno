import AVKit
import Foundation

/// Coordinates HTML5 video PiP inside WKWebView. There is intentionally no private API and
/// no native AVPlayerLayer fallback: the page's own video element must support PiP.
@MainActor
final class WebPictureInPictureCoordinator: ObservableObject {
    enum State: Equatable {
        case unknown
        case available
        case starting
        case active
        case unavailable(PiPFailureReason)

        var isActive: Bool { self == .active }

        var displayText: String {
            switch self {
            case .unknown: return "未知"
            case .available: return "可用"
            case .starting: return "正在启动"
            case .active: return "画中画显示中"
            case .unavailable(let reason): return reason.userMessage
            }
        }
    }

    @Published private(set) var state: State = .unknown
    @Published private(set) var lastFailure: PiPFailureReason?
    @Published private(set) var lastAttemptAt: Date?
    @Published private(set) var lastSuccessMethod: String?

    private let mediaDetector: MediaDetector
    private let configurationAllowsPiP: () -> Bool
    private let platformSupportProvider: () -> Bool
    private let now: () -> Date
    private var activeSince: Date?

    /// Emits typed diagnostics; AppCoordinator bridges this to DiagnosticsStore.
    var onOutcome: ((PiPRequestOutcome, PiPAvailability) -> Void)?
    var onStateChanged: ((State) -> Void)?

    init(
        mediaDetector: MediaDetector,
        configurationAllowsPiP: @escaping () -> Bool,
        platformSupportsPiP: @escaping () -> Bool = {
            AVPictureInPictureController.isPictureInPictureSupported()
        },
        now: @escaping () -> Date = Date.init
    ) {
        self.mediaDetector = mediaDetector
        self.configurationAllowsPiP = configurationAllowsPiP
        self.platformSupportProvider = platformSupportsPiP
        self.now = now
    }

    var platformSupportsPiP: Bool {
        platformSupportProvider()
    }

    var isActive: Bool {
        state == .active
    }

    /// Pure-ish availability computation based on platform, configuration and the latest
    /// probe aggregate. UI and tests use the same source of truth.
    var availability: PiPAvailability {
        if !platformSupportsPiP {
            return PiPAvailability(isAvailable: false, reason: .platformUnsupported)
        }
        if !configurationAllowsPiP() {
            return PiPAvailability(isAvailable: false, reason: .webViewConfigurationDisabled)
        }
        if mediaDetector.lastSnapshotReceivedAt == nil {
            return PiPAvailability(isAvailable: false, reason: .probeUnavailable)
        }
        let aggregate = mediaDetector.aggregate
        guard aggregate.hasAnyVideo else {
            return PiPAvailability(isAvailable: false, reason: .noVideo)
        }
        guard aggregate.hasPlayingVideo else {
            return PiPAvailability(isAvailable: false, reason: .videoNotPlaying)
        }
        if let best = aggregate.bestVideo, best.pipFeatureAllowed == false {
            return PiPAvailability(isAvailable: false, reason: .featurePolicyDenied)
        }
        guard aggregate.hasPiPCapablePlayingVideo else {
            return PiPAvailability(isAvailable: false, reason: .pageDoesNotSupportPiP)
        }
        return PiPAvailability(isAvailable: true, reason: nil)
    }

    /// Refreshes the published state without starting anything.
    func refreshAvailability() {
        let availability = self.availability
        guard !state.isActive, state != .starting else { return }
        if availability.isAvailable {
            state = .available
        } else if let reason = availability.reason {
            state = .unavailable(reason)
        }
    }

    @discardableResult
    func requestPiP() async -> PiPRequestOutcome {
        lastAttemptAt = now()
        let availability = self.availability
        guard let videoIndex = availability.isAvailable ? mediaDetector.aggregate.bestVideo?.index : nil else {
            let reason = availability.reason ?? .unknown
            lastFailure = reason
            state = .unavailable(reason)
            let outcome = PiPRequestOutcome.failure(reason: reason, detail: nil)
            onOutcome?(outcome, availability)
            onStateChanged?(state)
            return outcome
        }

        // A video in a cross-origin iframe cannot be reached by main-frame JavaScript.
        // Do not misreport it as "no video"; direct the user to the in-page control that the
        // subframe's own probe exposes.
        if Self.requiresInPageControl(for: mediaDetector.aggregate) {
            _ = mediaDetector.showInPagePiPControl()
            lastFailure = .requiresUserGesture
            state = .available
            let outcome = PiPRequestOutcome.failure(
                reason: .requiresUserGesture,
                detail: "pip-capable video is in a subframe; use the in-page control"
            )
            onOutcome?(outcome, availability)
            onStateChanged?(state)
            return outcome
        }

        state = .starting
        onStateChanged?(state)
        let outcome = await mediaDetector.requestPiP(videoIndex: videoIndex)
        lastAttemptAt = now()

        switch outcome {
        case .success(let method):
            lastSuccessMethod = method
            lastFailure = nil
            state = .active
            activeSince = now()
        case .failure(let reason, _):
            lastFailure = reason
            if reason == .requiresUserGesture {
                // Surface the in-page control; a genuine web-content tap is required.
                _ = mediaDetector.showInPagePiPControl()
                state = .available
            } else {
                state = .unavailable(reason)
            }
        }
        onOutcome?(outcome, availability)
        onStateChanged?(state)
        return outcome
    }

    /// Media events are authoritative for PiP visibility; snapshots can only upgrade the
    /// state (e.g. PiP was entered through the system video controls).
    /// WKWebView's `evaluateJavaScript` cannot reach a cross-origin subframe. If the only
    /// PiP-capable playing video lives there, the user must use that frame's in-page control.
    nonisolated static func requiresInPageControl(for aggregate: MediaAggregate) -> Bool {
        aggregate.hasPiPCapablePlayingVideo
            && !aggregate.mainFrameHasPiPCapablePlayingVideo
    }

    func handle(event: MediaPlaybackEvent) {
        if event.name == .enterpictureinpicture {
            lastFailure = nil
            state = .active
            activeSince = now()
            onStateChanged?(state)
        } else if event.name == .leavepictureinpicture {
            state = .available
            activeSince = nil
            onStateChanged?(state)
        }
    }

    func handle(aggregate: MediaAggregate, snapshotReceivedAt: Date?) {
        if aggregate.isInPiP {
            if state != .active {
                state = .active
                activeSince = now()
                onStateChanged?(state)
            }
            return
        }
        guard state == .active else { return }
        // Downgrade only on a fresh snapshot that was observed after PiP had been active for
        // at least 2 seconds. This avoids racing a snapshot that was queued before entry.
        guard let activeSince,
              now().timeIntervalSince(activeSince) > 2,
              let snapshotReceivedAt,
              snapshotReceivedAt > activeSince,
              now().timeIntervalSince(snapshotReceivedAt) < 3 else {
            return
        }
        state = .available
        self.activeSince = nil
        onStateChanged?(state)
    }

    func exitPiP() {
        mediaDetector.exitPiP()
    }
}

struct PiPAvailability: Equatable {
    let isAvailable: Bool
    let reason: PiPFailureReason?
}
