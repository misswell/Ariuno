import Foundation

/// Bridges browser/media/network events into the pure session state machine and publishes a
/// diagnostic snapshot. It never reloads anything by itself and never claims server-side
/// session continuity.
@MainActor
final class SessionMonitor: ObservableObject {
    @Published private(set) var state: GameSessionState = .idle
    @Published private(set) var failureReason: String?
    @Published private(set) var lastPiPFailureReason: String?
    @Published private(set) var pipVisible: Bool = false
    @Published private(set) var mediaPlayingObserved: Bool = false
    @Published private(set) var lastMediaActivityAt: Date?
    @Published private(set) var lastPlayingObservedAt: Date?
    @Published private(set) var lastForegroundAt: Date?
    @Published private(set) var lastBackgroundAt: Date?
    @Published private(set) var appIsForeground: Bool = true
    @Published private(set) var networkStatus: NetworkStatus = .unknown
    @Published private(set) var recoveryAttempts: Int = 0
    @Published private(set) var transitionCount: Int = 0
    @Published private(set) var lastTransitionAt: Date?
    @Published private(set) var lastEventSummary: String = ""
    @Published private(set) var mediaProbePolling: Bool = false

    /// There is no public API that proves the cloud-side session is alive. This stays false.
    let serverSessionVerified = false

    private(set) var machine = SessionStateMachine()
    private let now: () -> Date
    private var stallTimer: Timer?
    private var lastStallSignalAt: Date?
    private var lastDiagnosticEvent: String = ""
    private var lastPiPStartedAt: Date?

    var onTransition: ((GameSessionState, GameSessionState) -> Void)?
    var onDiagnostic: ((DiagnosticSeverity, String, String, [String: String]) -> Void)?

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    var verification: PlaybackVerification {
        PlaybackVerification(
            pipVisible: pipVisible,
            mediaFlowingObserved: mediaPlayingObserved,
            serverSessionVerified: false
        )
    }

    var diagnosticsSnapshot: SessionDiagnosticsSnapshot {
        SessionDiagnosticsSnapshot(
            state: state,
            failureReason: failureReason,
            lastPiPFailureReason: lastPiPFailureReason,
            pipVisible: pipVisible,
            mediaPlayingObserved: mediaPlayingObserved,
            lastMediaActivityAt: lastMediaActivityAt,
            lastPlayingObservedAt: lastPlayingObservedAt,
            lastForegroundAt: lastForegroundAt,
            lastBackgroundAt: lastBackgroundAt,
            appIsForeground: appIsForeground,
            networkStatus: networkStatus.rawValue,
            recoveryAttempts: recoveryAttempts,
            serverSessionVerified: false,
            mediaProbePolling: mediaProbePolling,
            recordedAt: now()
        )
    }

    // MARK: - Navigation

    func startLoading() {
        stopStallWatchdog()
        apply(.beginLoad, summary: "开始加载官方页面", severity: .info)
    }

    func navigationCommitted() {
        apply(.navigationCommitted, summary: "收到首个内容响应", severity: .debug)
    }

    func loadFinished() {
        stopStallWatchdog()
        apply(.loadFinished, summary: "页面加载完成", severity: .info)
    }

    func navigationFailed(_ reason: String) {
        stopStallWatchdog()
        apply(
            .loadFailed(PrivacyRedactor.redact(reason)),
            summary: "主框架导航失败",
            severity: .error,
            metadata: ["reason": reason]
        )
    }

    func markUnsupported(reason: String) {
        apply(
            .unsupported(PrivacyRedactor.redact(reason)),
            summary: "标记为不支持/待验证",
            severity: .warning
        )
    }

    // MARK: - Media

    func handle(mediaAggregate aggregate: MediaAggregate, snapshotReceivedAt: Date?) {
        if aggregate.hasPlayingVideo {
            stopStallWatchdog()
        }
        let previousState = state
        let previousPip = pipVisible
        apply(
            .mediaObserved(hasVideo: aggregate.hasAnyVideo, isPlaying: aggregate.hasPlayingVideo),
            summary: "媒体快照 \(aggregate.summaryText)",
            severity: .debug,
            metadata: aggregateMetadata(aggregate)
        )
        let pipSettled = lastPiPStartedAt.map { now().timeIntervalSince($0) > 2 } ?? true
        let snapshotIsFresh = snapshotReceivedAt.map { now().timeIntervalSince($0) < 3 } ?? false
        reconcilePiP(
            isInPiP: aggregate.isInPiP,
            snapshotIsFresh: snapshotIsFresh && pipSettled
        )
        if previousState != state || previousPip != pipVisible {
            onDiagnostic?(
                .info,
                "session.media_state",
                "媒体观测已更新会话状态",
                aggregateMetadata(aggregate)
            )
        }
    }

    func handle(mediaEvent event: MediaPlaybackEvent) {
        switch event.name {
        case .playing:
            stopStallWatchdog()
            apply(
                .playback(.playing),
                summary: "媒体开始播放",
                severity: .info,
                metadata: eventMetadata(event)
            )
        case .pause:
            apply(
                .playback(.paused),
                summary: "媒体暂停",
                severity: .debug,
                metadata: eventMetadata(event)
            )
        case .waiting:
            apply(
                .playback(.waiting),
                summary: "媒体等待数据",
                severity: .warning,
                metadata: eventMetadata(event)
            )
            startStallWatchdog(reason: "waiting")
        case .stalled:
            apply(
                .playback(.stalled),
                summary: "媒体停滞",
                severity: .warning,
                metadata: eventMetadata(event)
            )
            startStallWatchdog(reason: "stalled")
        case .emptied:
            apply(
                .playback(.emptied),
                summary: "媒体源被清空",
                severity: .warning,
                metadata: eventMetadata(event)
            )
            startStallWatchdog(reason: "emptied")
        case .error:
            apply(
                .playback(.error("视频元素报告错误")),
                summary: "视频元素错误",
                severity: .error,
                metadata: eventMetadata(event)
            )
            startStallWatchdog(reason: "error")
        case .enterpictureinpicture:
            stopStallWatchdog()
            apply(
                .pipStarted,
                summary: "已进入系统画中画",
                severity: .info,
                metadata: eventMetadata(event)
            )
        case .leavepictureinpicture:
            apply(
                .pipStopped,
                summary: "已退出系统画中画（服务器会话 UNVERIFIED）",
                severity: .info,
                metadata: eventMetadata(event)
            )
        case .presentationmodechanged:
            if event.isPiPActive {
                apply(.pipStarted, summary: "演示模式变为画中画", severity: .info)
            } else if pipVisible {
                apply(.pipStopped, summary: "演示模式离开画中画", severity: .info)
            } else {
                apply(.mediaObserved(hasVideo: event.hasVideo, isPlaying: false),
                      summary: "演示模式变化", severity: .debug)
            }
        case .loadedmetadata, .loadeddata, .visibilitychange, .domchanged:
            apply(
                .mediaObserved(hasVideo: event.hasVideo, isPlaying: event.isPlaying ?? mediaPlayingObserved),
                summary: "媒体事件 \(event.name.rawValue)",
                severity: .debug,
                metadata: eventMetadata(event)
            )
        }
    }

    func reconcilePiP(isInPiP: Bool, snapshotIsFresh: Bool) {
        if isInPiP && !pipVisible {
            apply(.pipStarted, summary: "快照显示画中画已激活", severity: .info)
        } else if !isInPiP && pipVisible && snapshotIsFresh {
            apply(.pipStopped, summary: "快照显示画中画已关闭", severity: .info)
        }
    }

    // MARK: - PiP requests

    func pipRequestStarted() {
        apply(.pipRequested, summary: "请求进入画中画", severity: .info)
    }

    func pipRequestFailed(reason: PiPFailureReason) {
        apply(
            .pipFailed(reason.rawValue),
            summary: "画中画请求失败：\(reason.userMessage)",
            severity: reason == .requiresUserGesture ? .info : .warning,
            metadata: ["reason": reason.rawValue]
        )
    }

    func pipBecameActive() {
        apply(.pipStarted, summary: "画中画协调器报告已激活", severity: .info)
    }

    func pipBecameInactive() {
        apply(.pipStopped, summary: "画中画协调器报告已关闭（服务器会话 UNVERIFIED）", severity: .info)
    }

    // MARK: - App lifecycle

    func appDidEnterBackground() {
        lastBackgroundAt = now()
        stopStallWatchdog()
        apply(.appBackgrounded, summary: "App 进入后台（不重载页面）", severity: .info)
    }

    func appDidBecomeActive() {
        lastForegroundAt = now()
        apply(.appForegrounded, summary: "App 回到前台（保留现有页面）", severity: .info)
    }

    func setNetworkStatus(_ status: NetworkStatus) {
        let previous = networkStatus
        networkStatus = status
        guard status != previous else { return }
        if status.isAvailable {
            apply(
                .networkRestored,
                summary: "网络可用：\(status.displayName)",
                severity: .info,
                metadata: ["interface": status.rawValue]
            )
        } else if status == .unavailable {
            apply(
                .networkLost,
                summary: "网络不可用",
                severity: .warning
            )
        }
    }

    func setMediaProbePolling(_ polling: Bool) {
        mediaProbePolling = polling
    }

    // MARK: - Failure / recovery

    func webContentTerminated() {
        stopStallWatchdog()
        apply(.processTerminated, summary: "WebContent 进程终止", severity: .error)
    }

    func recoveryStarted() {
        recoveryAttempts += 1
        apply(
            .recoveryStarted,
            summary: "用户确认后开始恢复（第 \(recoveryAttempts) 次）",
            severity: .info,
            metadata: ["attempt": String(recoveryAttempts)]
        )
    }

    func recoverySucceeded() {
        apply(.recoverySucceeded, summary: "恢复后的页面已就绪", severity: .info)
    }

    func recoveryFailed(_ reason: String) {
        apply(
            .recoveryFailed(PrivacyRedactor.redact(reason)),
            summary: "恢复失败",
            severity: .error
        )
    }

    func userExited() {
        stopStallWatchdog()
        recoveryAttempts = 0
        apply(.userExited, summary: "用户退出会话", severity: .info)
    }

    // MARK: - Internals

    private func apply(
        _ event: SessionEvent,
        summary: String,
        severity: DiagnosticSeverity,
        metadata: [String: String] = [:]
    ) {
        let previous = machine.state
        if event == .pipStarted {
            lastPiPStartedAt = now()
        } else if event == .pipStopped || event == .userExited {
            lastPiPStartedAt = nil
        }
        let next = machine.handle(event, at: now())
        syncFromMachine()
        lastEventSummary = summary

        if next != previous {
            transitionCount += 1
            lastTransitionAt = now()
            onTransition?(previous, next)
            onDiagnostic?(
                .info,
                "session.state",
                "\(previous.displayName) → \(next.displayName)",
                metadata
            )
        } else if lastDiagnosticEvent != "\(event)" {
            lastDiagnosticEvent = "\(event)"
            onDiagnostic?(severity, "session.event", summary, metadata)
        }
    }

    private func syncFromMachine() {
        state = machine.state
        failureReason = machine.failureReason
        lastPiPFailureReason = machine.lastPiPFailureReason
        pipVisible = machine.isPiPVisible
        mediaPlayingObserved = machine.isMediaPlaying
        appIsForeground = machine.appIsForeground
        lastMediaActivityAt = machine.lastMediaActivityAt
        lastPlayingObservedAt = machine.lastPlayingObservedAt
    }

    private func startStallWatchdog(reason: String) {
        guard appIsForeground else { return }
        lastStallSignalAt = now()
        stallTimer?.invalidate()
        let timer = Timer(timeInterval: FeatureFlags.mediaStallConfirmationDelay, repeats: false) {
            [weak self] _ in
            Task { @MainActor in
                self?.confirmStallIfStillStalled(reason: reason)
            }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        stallTimer = timer
    }

    private func confirmStallIfStillStalled(reason: String) {
        stallTimer = nil
        guard appIsForeground else { return }
        guard !mediaPlayingObserved else { return }
        let elapsed: Int
        if let lastStallSignalAt {
            elapsed = Int(now().timeIntervalSince(lastStallSignalAt))
        } else {
            elapsed = Int(FeatureFlags.mediaStallConfirmationDelay)
        }
        apply(
            .stallConfirmed("视频约 \(elapsed) 秒无进展（\(reason)）"),
            summary: "媒体停滞已确认",
            severity: .warning,
            metadata: ["reason": reason]
        )
    }

    private func stopStallWatchdog() {
        stallTimer?.invalidate()
        stallTimer = nil
        lastStallSignalAt = nil
    }

    private func aggregateMetadata(_ aggregate: MediaAggregate) -> [String: String] {
        [
            "frames": String(aggregate.frameCount),
            "videos": String(aggregate.videoCount),
            "playing": String(aggregate.playingVideoCount),
            "pipVideos": String(aggregate.piPCapablePlayingVideoCount),
            "kind": aggregate.kind.rawValue,
            "origins": aggregate.origins.joined(separator: ",")
        ]
    }

    private func eventMetadata(_ event: MediaPlaybackEvent) -> [String: String] {
        var metadata: [String: String] = [
            "event": event.name.rawValue,
            "origin": event.origin,
            "topFrame": event.isTopFrame ? "1" : "0"
        ]
        if let index = event.videoIndex { metadata["videoIndex"] = String(index) }
        if let mode = event.presentationMode { metadata["mode"] = mode }
        if let readyState = event.readyState { metadata["readyState"] = String(readyState) }
        return metadata
    }
}
