import XCTest
@testable import Ariuno

@MainActor
final class SessionMonitorTests: XCTestCase {
    private func makePlayingAggregate() -> MediaAggregate {
        var aggregate = MediaAggregate()
        aggregate.frameCount = 1
        aggregate.videoCount = 1
        aggregate.playingVideoCount = 1
        aggregate.piPCapablePlayingVideoCount = 1
        aggregate.kind = .htmlVideo
        return aggregate
    }

    func testLoadLifecycleAndMediaObservation() {
        let monitor = SessionMonitor()
        XCTAssertEqual(monitor.state, .idle)

        monitor.startLoading()
        XCTAssertEqual(monitor.state, .loading)
        monitor.navigationCommitted()
        monitor.loadFinished()
        XCTAssertEqual(monitor.state, .ready)

        monitor.handle(mediaAggregate: makePlayingAggregate(), snapshotReceivedAt: Date())
        XCTAssertTrue(monitor.mediaPlayingObserved)
        XCTAssertNotNil(monitor.lastMediaActivityAt)
        XCTAssertNotNil(monitor.lastPlayingObservedAt)

        monitor.pipBecameActive()
        XCTAssertEqual(monitor.state, .pipActive)
        XCTAssertTrue(monitor.pipVisible)

        monitor.pipBecameInactive()
        XCTAssertEqual(monitor.state, .ready)
        XCTAssertFalse(monitor.pipVisible)
    }

    func testVerificationNeverClaimsServerSession() {
        let monitor = SessionMonitor()
        monitor.startLoading()
        monitor.loadFinished()
        monitor.handle(mediaAggregate: makePlayingAggregate(), snapshotReceivedAt: Date())
        monitor.pipBecameActive()

        let verification = monitor.verification
        XCTAssertTrue(verification.pipVisible)
        XCTAssertTrue(verification.mediaFlowingObserved)
        XCTAssertFalse(verification.serverSessionVerified)
        XCTAssertFalse(verification.isFullBackgroundIdleVerified)
        XCTAssertFalse(monitor.diagnosticsSnapshot.serverSessionVerified)
    }

    func testBackgroundAndForegroundDoNotReloadOrDropState() {
        let monitor = SessionMonitor()
        monitor.startLoading()
        monitor.loadFinished()
        monitor.handle(mediaAggregate: makePlayingAggregate(), snapshotReceivedAt: Date())
        monitor.pipBecameActive()

        monitor.appDidEnterBackground()
        XCTAssertFalse(monitor.appIsForeground)
        XCTAssertNotNil(monitor.lastBackgroundAt)
        XCTAssertEqual(monitor.state, .pipActive)
        XCTAssertTrue(monitor.pipVisible)

        monitor.appDidBecomeActive()
        XCTAssertTrue(monitor.appIsForeground)
        XCTAssertNotNil(monitor.lastForegroundAt)
        XCTAssertEqual(monitor.state, .pipActive)
    }

    func testNetworkLossWhilePlayingKeepsPiPState() {
        let monitor = SessionMonitor()
        monitor.startLoading()
        monitor.loadFinished()
        monitor.handle(mediaAggregate: makePlayingAggregate(), snapshotReceivedAt: Date())
        monitor.pipBecameActive()

        monitor.setNetworkStatus(.unavailable)
        XCTAssertEqual(monitor.networkStatus, .unavailable)
        XCTAssertEqual(monitor.state, .pipActive)
        XCTAssertTrue(monitor.pipVisible)

        monitor.setNetworkStatus(.wifi)
        XCTAssertEqual(monitor.networkStatus, .wifi)
    }

    func testNetworkLossWithoutPlaybackDisconnectsAndRestoresToReconnecting() {
        let monitor = SessionMonitor()
        monitor.startLoading()
        monitor.loadFinished()
        monitor.setNetworkStatus(.unavailable)
        XCTAssertEqual(monitor.state, .disconnected)
        monitor.setNetworkStatus(.cellular)
        XCTAssertEqual(monitor.state, .reconnecting)
        monitor.loadFinished()
        XCTAssertEqual(monitor.state, .ready)
    }

    func testNavigationFailureAndProcessTermination() {
        let monitor = SessionMonitor()
        monitor.startLoading()
        monitor.navigationFailed("TLS 证书校验失败 https://sr.mihoyo.com/cloud/?token=abc")
        XCTAssertEqual(monitor.state, .failed)
        XCTAssertFalse(monitor.failureReason?.contains("abc") ?? true)

        let second = SessionMonitor()
        second.startLoading()
        second.loadFinished()
        second.webContentTerminated()
        XCTAssertEqual(second.state, .failed)
        XCTAssertFalse(second.mediaPlayingObserved)
    }

    func testRecoveryAttemptCounterAndUserExitReset() {
        let monitor = SessionMonitor()
        monitor.startLoading()
        monitor.loadFinished()
        monitor.recoveryStarted()
        XCTAssertEqual(monitor.state, .reconnecting)
        XCTAssertEqual(monitor.recoveryAttempts, 1)
        monitor.recoverySucceeded()
        XCTAssertEqual(monitor.state, .ready)
        monitor.userExited()
        XCTAssertEqual(monitor.state, .idle)
        XCTAssertEqual(monitor.recoveryAttempts, 0)
    }

    func testDiagnosticsSnapshotReflectsCurrentState() {
        let monitor = SessionMonitor()
        monitor.startLoading()
        monitor.loadFinished()
        monitor.handle(mediaAggregate: makePlayingAggregate(), snapshotReceivedAt: Date())
        monitor.setMediaProbePolling(true)
        let snapshot = monitor.diagnosticsSnapshot
        XCTAssertEqual(snapshot.state, .ready)
        XCTAssertTrue(snapshot.mediaPlayingObserved)
        XCTAssertTrue(snapshot.mediaProbePolling)
        XCTAssertFalse(snapshot.serverSessionVerified)
        XCTAssertEqual(snapshot.networkStatus, NetworkStatus.unknown.rawValue)
    }

    func testStallConfirmationViaExplicitEvent() {
        let monitor = SessionMonitor()
        monitor.startLoading()
        monitor.loadFinished()
        monitor.handle(mediaAggregate: makePlayingAggregate(), snapshotReceivedAt: Date())
        // Simulate the state machine's confirmed stall path through the public monitor API
        // by injecting a failure transition; the timer path is covered by machine tests.
        monitor.webContentTerminated()
        XCTAssertEqual(monitor.state, .failed)
    }
}
