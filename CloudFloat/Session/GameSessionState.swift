import Foundation

/// The user-visible session state. PiP visibility and server-side session continuity are
/// tracked separately because they are independent facts.
enum GameSessionState: String, Codable, CaseIterable, Equatable {
    case idle
    case loading
    case ready
    case pipStarting
    case pipActive
    case streamStalled
    case reconnecting
    case disconnected
    case unsupported
    case failed

    var displayName: String {
        switch self {
        case .idle: return "空闲"
        case .loading: return "加载中"
        case .ready: return "页面就绪"
        case .pipStarting: return "画中画启动中"
        case .pipActive: return "画中画显示中"
        case .streamStalled: return "媒体流停滞"
        case .reconnecting: return "重连中"
        case .disconnected: return "已断线"
        case .unsupported: return "不支持/待验证"
        case .failed: return "故障"
        }
    }

    var isTerminalFailure: Bool {
        self == .failed
    }
}

enum PlaybackSignal: Equatable {
    case playing
    case paused
    case waiting
    case stalled
    case emptied
    case error(String)
}

enum SessionEvent: Equatable {
    case beginLoad
    case navigationCommitted
    case loadFinished
    case loadFailed(String)
    case unsupported(String)
    case mediaObserved(hasVideo: Bool, isPlaying: Bool)
    case playback(PlaybackSignal)
    case pipRequested
    case pipStarted
    case pipFailed(String)
    case pipStopped
    case stallConfirmed(String)
    case appBackgrounded
    case appForegrounded
    case networkLost
    case networkRestored
    case processTerminated
    case recoveryStarted
    case recoverySucceeded
    case recoveryFailed(String)
    case userExited
}

/// Pure state machine, free of WebKit/UIKit so every transition is unit-testable.
struct SessionStateMachine {
    private(set) var state: GameSessionState = .idle
    private(set) var failureReason: String?
    private(set) var lastPiPFailureReason: String?
    private(set) var lastMediaActivityAt: Date?
    private(set) var lastPlayingObservedAt: Date?
    private(set) var stalledSince: Date?
    private(set) var isPiPVisible = false
    private(set) var isMediaPlaying = false
    private(set) var appIsForeground = true
    private(set) var hasLoadedPage = false
    private(set) var networkAvailable = true
    private(set) var pipEverStarted = false

    @discardableResult
    mutating func handle(_ event: SessionEvent, at date: Date = Date()) -> GameSessionState {
        switch event {
        case .beginLoad:
            state = .loading
            failureReason = nil
            lastPiPFailureReason = nil
            stalledSince = nil
            hasLoadedPage = false
            isMediaPlaying = false
            isPiPVisible = false

        case .navigationCommitted:
            hasLoadedPage = true
            if state == .idle {
                state = .loading
            }

        case .loadFinished:
            hasLoadedPage = true
            failureReason = nil
            if state != .pipActive {
                state = .ready
            }

        case .loadFailed(let reason):
            state = .failed
            failureReason = reason
            hasLoadedPage = false
            isPiPVisible = false
            isMediaPlaying = false

        case .unsupported(let reason):
            state = .unsupported
            failureReason = reason

        case .mediaObserved(let hasVideo, let isPlaying):
            if hasVideo {
                lastMediaActivityAt = date
            }
            if isPlaying {
                lastPlayingObservedAt = date
                lastMediaActivityAt = date
            }
            isMediaPlaying = isPlaying
            if isPlaying {
                stalledSince = nil
                if isPiPVisible {
                    state = .pipActive
                } else if state == .loading || state == .reconnecting ||
                            state == .disconnected || state == .streamStalled ||
                            state == .unsupported {
                    state = .ready
                    failureReason = nil
                }
            }

        case .playback(let signal):
            switch signal {
            case .playing:
                isMediaPlaying = true
                stalledSince = nil
                lastPlayingObservedAt = date
                lastMediaActivityAt = date
                if isPiPVisible {
                    state = .pipActive
                } else if state == .loading || state == .reconnecting ||
                            state == .disconnected || state == .streamStalled ||
                            state == .unsupported {
                    state = .ready
                    failureReason = nil
                }
            case .paused:
                isMediaPlaying = false
                lastMediaActivityAt = date
            case .waiting, .stalled:
                isMediaPlaying = false
                stalledSince = date
            case .emptied:
                isMediaPlaying = false
                stalledSince = date
            case .error(let reason):
                isMediaPlaying = false
                stalledSince = date
                failureReason = reason
                if state == .pipActive || state == .ready {
                    state = .streamStalled
                }
            }

        case .pipRequested:
            lastPiPFailureReason = nil
            if state == .ready || state == .streamStalled {
                state = .pipStarting
            }

        case .pipStarted:
            isPiPVisible = true
            pipEverStarted = true
            lastPiPFailureReason = nil
            failureReason = nil
            state = .pipActive

        case .pipFailed(let reason):
            lastPiPFailureReason = reason
            if isPiPVisible {
                state = .pipActive
            } else if state == .pipStarting {
                // A PiP failure does not end the game; the page keeps running.
                state = .ready
            }

        case .pipStopped:
            isPiPVisible = false
            if state == .pipActive || state == .pipStarting {
                // Closing the floating window is not a session exit and must not reload.
                state = .ready
            }

        case .stallConfirmed(let reason):
            if state == .pipActive || state == .ready || state == .pipStarting {
                state = .streamStalled
                failureReason = reason
            }

        case .appBackgrounded:
            appIsForeground = false

        case .appForegrounded:
            appIsForeground = true

        case .networkLost:
            networkAvailable = false
            if !isMediaPlaying && state != .idle && state != .unsupported && state != .failed {
                state = .disconnected
                failureReason = "网络不可用"
            }

        case .networkRestored:
            networkAvailable = true
            if state == .disconnected || state == .streamStalled {
                state = .reconnecting
            }

        case .processTerminated:
            state = .failed
            failureReason = "WebContent 进程已终止"
            hasLoadedPage = false
            isPiPVisible = false
            isMediaPlaying = false
            stalledSince = nil

        case .recoveryStarted:
            state = .reconnecting
            failureReason = nil
            stalledSince = nil

        case .recoverySucceeded:
            state = .ready
            failureReason = nil

        case .recoveryFailed(let reason):
            state = .failed
            failureReason = reason

        case .userExited:
            state = .idle
            failureReason = nil
            lastPiPFailureReason = nil
            lastMediaActivityAt = nil
            lastPlayingObservedAt = nil
            stalledSince = nil
            isPiPVisible = false
            isMediaPlaying = false
            hasLoadedPage = false
            networkAvailable = true
            pipEverStarted = false
        }
        return state
    }
}

/// Three independent layers. Only all three together would constitute a background-idle
/// success. `serverSessionVerified` is intentionally false: no public API can prove that the
/// cloud-side game session and auto-battle are still running.
struct PlaybackVerification: Equatable {
    let pipVisible: Bool
    let mediaFlowingObserved: Bool
    let serverSessionVerified: Bool

    static let noServerProof = PlaybackVerification(
        pipVisible: false,
        mediaFlowingObserved: false,
        serverSessionVerified: false
    )

    var isFullBackgroundIdleVerified: Bool {
        pipVisible && mediaFlowingObserved && serverSessionVerified
    }

    var overallText: String {
        if isFullBackgroundIdleVerified {
            return "三层均已验证"
        }
        if pipVisible && mediaFlowingObserved {
            return "画中画与媒体层成立，服务器会话 UNVERIFIED"
        }
        if pipVisible {
            return "仅确认画中画浮窗存在，媒体实时性待验证"
        }
        return "未验证"
    }
}

struct SessionDiagnosticsSnapshot: Codable, Equatable {
    let state: GameSessionState
    let failureReason: String?
    let lastPiPFailureReason: String?
    let pipVisible: Bool
    let mediaPlayingObserved: Bool
    let lastMediaActivityAt: Date?
    let lastPlayingObservedAt: Date?
    let lastForegroundAt: Date?
    let lastBackgroundAt: Date?
    let appIsForeground: Bool
    let networkStatus: String
    let recoveryAttempts: Int
    let serverSessionVerified: Bool
    let mediaProbePolling: Bool
    let recordedAt: Date
}
