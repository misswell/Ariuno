import XCTest
@testable import Ariuno

final class GameSessionStateTests: XCTestCase {
    private var machine: SessionStateMachine!
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUp() {
        super.setUp()
        machine = SessionStateMachine()
    }

    private func loadAndPlay() {
        machine.handle(.beginLoad, at: t0)
        machine.handle(.navigationCommitted, at: t0.addingTimeInterval(1))
        machine.handle(.loadFinished, at: t0.addingTimeInterval(2))
        machine.handle(
            .mediaObserved(hasVideo: true, isPlaying: true),
            at: t0.addingTimeInterval(3)
        )
    }

    func testInitialStateIsIdle() {
        XCTAssertEqual(machine.state, .idle)
        XCTAssertFalse(machine.hasLoadedPage)
        XCTAssertFalse(machine.isPiPVisible)
        XCTAssertTrue(machine.appIsForeground)
    }

    func testHappyPathFromLoadingToPiPAndBack() {
        XCTAssertEqual(machine.handle(.beginLoad, at: t0), .loading)
        XCTAssertEqual(
            machine.handle(.navigationCommitted, at: t0.addingTimeInterval(1)),
            .loading
        )
        XCTAssertTrue(machine.hasLoadedPage)
        XCTAssertEqual(
            machine.handle(.loadFinished, at: t0.addingTimeInterval(2)),
            .ready
        )

        machine.handle(
            .mediaObserved(hasVideo: true, isPlaying: true),
            at: t0.addingTimeInterval(3)
        )
        XCTAssertTrue(machine.isMediaPlaying)
        XCTAssertNotNil(machine.lastPlayingObservedAt)

        machine.handle(.pipRequested, at: t0.addingTimeInterval(4))
        XCTAssertEqual(machine.state, .pipStarting)
        machine.handle(.pipStarted, at: t0.addingTimeInterval(5))
        XCTAssertEqual(machine.state, .pipActive)
        XCTAssertTrue(machine.isPiPVisible)
        XCTAssertTrue(machine.pipEverStarted)

        // Closing the floating window is not a session exit and must not mark failure.
        machine.handle(.pipStopped, at: t0.addingTimeInterval(6))
        XCTAssertEqual(machine.state, .ready)
        XCTAssertFalse(machine.isPiPVisible)
        XCTAssertTrue(machine.hasLoadedPage)
        XCTAssertNil(machine.failureReason)
    }

    func testBackgroundAndForegroundPreserveStateAndPage() {
        loadAndPlay()
        machine.handle(.pipStarted, at: t0.addingTimeInterval(4))
        machine.handle(.appBackgrounded, at: t0.addingTimeInterval(5))
        XCTAssertFalse(machine.appIsForeground)
        XCTAssertEqual(machine.state, .pipActive)
        XCTAssertTrue(machine.hasLoadedPage)
        XCTAssertTrue(machine.isPiPVisible)

        machine.handle(.appForegrounded, at: t0.addingTimeInterval(300))
        XCTAssertTrue(machine.appIsForeground)
        XCTAssertEqual(machine.state, .pipActive)
        XCTAssertTrue(machine.hasLoadedPage)
    }

    func testMediaPlayingRecoversFromReconnectingAndStalled() {
        loadAndPlay()
        machine.handle(.networkLost, at: t0.addingTimeInterval(4))
        // Still "playing" from the last snapshot, so buffered frames may keep the PiP state.
        XCTAssertEqual(machine.state, .ready)

        machine.handle(.playback(.waiting), at: t0.addingTimeInterval(5))
        machine.handle(.stallConfirmed("no progress"), at: t0.addingTimeInterval(13))
        XCTAssertEqual(machine.state, .streamStalled)

        machine.handle(.playback(.playing), at: t0.addingTimeInterval(14))
        XCTAssertEqual(machine.state, .ready)
        XCTAssertTrue(machine.isMediaPlaying)
    }

    func testNetworkLossWhileNotPlayingDisconnects() {
        loadAndPlay()
        machine.handle(.playback(.paused), at: t0.addingTimeInterval(4))
        machine.handle(.networkLost, at: t0.addingTimeInterval(5))
        XCTAssertEqual(machine.state, .disconnected)
        XCTAssertFalse(machine.networkAvailable)

        machine.handle(.networkRestored, at: t0.addingTimeInterval(6))
        XCTAssertEqual(machine.state, .reconnecting)
        XCTAssertTrue(machine.networkAvailable)

        machine.handle(.loadFinished, at: t0.addingTimeInterval(7))
        XCTAssertEqual(machine.state, .ready)
    }

    func testNetworkLossWhilePiPActiveAndPlayingDoesNotDropPiP() {
        loadAndPlay()
        machine.handle(.pipStarted, at: t0.addingTimeInterval(4))
        machine.handle(.networkLost, at: t0.addingTimeInterval(5))
        XCTAssertEqual(machine.state, .pipActive)
        XCTAssertTrue(machine.isPiPVisible)
    }

    func testPiPFailureKeepsGameRunning() {
        loadAndPlay()
        machine.handle(.pipRequested, at: t0.addingTimeInterval(4))
        machine.handle(.pipFailed("requiresUserGesture"), at: t0.addingTimeInterval(5))
        XCTAssertEqual(machine.state, .ready)
        XCTAssertFalse(machine.isPiPVisible)
        XCTAssertEqual(machine.lastPiPFailureReason, "requiresUserGesture")
        XCTAssertTrue(machine.hasLoadedPage)
    }

    func testStallConfirmationAfterWaiting() {
        loadAndPlay()
        machine.handle(.playback(.waiting), at: t0.addingTimeInterval(4))
        XCTAssertEqual(machine.state, .ready)
        machine.handle(.stallConfirmed("waiting 8s"), at: t0.addingTimeInterval(12))
        XCTAssertEqual(machine.state, .streamStalled)
        XCTAssertEqual(machine.failureReason, "waiting 8s")
    }

    func testVideoErrorTransitionsToStalled() {
        loadAndPlay()
        machine.handle(.playback(.error("decode error")), at: t0.addingTimeInterval(4))
        XCTAssertEqual(machine.state, .streamStalled)
        XCTAssertFalse(machine.isMediaPlaying)
    }

    func testProcessTerminationClearsPiPAndRequiresRecovery() {
        loadAndPlay()
        machine.handle(.pipStarted, at: t0.addingTimeInterval(4))
        machine.handle(.processTerminated, at: t0.addingTimeInterval(5))
        XCTAssertEqual(machine.state, .failed)
        XCTAssertFalse(machine.isPiPVisible)
        XCTAssertFalse(machine.hasLoadedPage)
        XCTAssertTrue(machine.failureReason?.contains("WebContent") == true)
    }

    func testRecoveryStartAndSuccess() {
        loadAndPlay()
        machine.handle(.processTerminated, at: t0.addingTimeInterval(4))
        machine.handle(.recoveryStarted, at: t0.addingTimeInterval(5))
        XCTAssertEqual(machine.state, .reconnecting)
        machine.handle(.navigationCommitted, at: t0.addingTimeInterval(6))
        machine.handle(.loadFinished, at: t0.addingTimeInterval(7))
        XCTAssertEqual(machine.state, .ready)
    }

    func testUnsupportedStateCanRecoverWhenVideoStartsPlaying() {
        machine.handle(.unsupported("no html video"), at: t0)
        XCTAssertEqual(machine.state, .unsupported)
        machine.handle(
            .mediaObserved(hasVideo: true, isPlaying: true),
            at: t0.addingTimeInterval(1)
        )
        XCTAssertEqual(machine.state, .ready)
    }

    func testUserExitResetsEverything() {
        loadAndPlay()
        machine.handle(.pipStarted, at: t0.addingTimeInterval(4))
        machine.handle(.userExited, at: t0.addingTimeInterval(5))
        XCTAssertEqual(machine.state, .idle)
        XCTAssertFalse(machine.isPiPVisible)
        XCTAssertFalse(machine.hasLoadedPage)
        XCTAssertFalse(machine.isMediaPlaying)
        XCTAssertNil(machine.failureReason)
        XCTAssertNil(machine.lastMediaActivityAt)
        XCTAssertFalse(machine.pipEverStarted)
    }

    func testPlaybackVerificationRequiresAllThreeLayers() {
        let incomplete = PlaybackVerification(
            pipVisible: true,
            mediaFlowingObserved: true,
            serverSessionVerified: false
        )
        XCTAssertFalse(incomplete.isFullBackgroundIdleVerified)
        XCTAssertTrue(incomplete.overallText.contains("UNVERIFIED"))

        let complete = PlaybackVerification(
            pipVisible: true,
            mediaFlowingObserved: true,
            serverSessionVerified: true
        )
        XCTAssertTrue(complete.isFullBackgroundIdleVerified)
    }

    func testPlayingObservationDoesNotSilentlyClearAFailedState() {
        machine.handle(.beginLoad, at: t0)
        machine.handle(.navigationCommitted, at: t0.addingTimeInterval(1))
        machine.handle(.loadFinished, at: t0.addingTimeInterval(2))
        machine.handle(.loadFailed("TLS certificate rejected"), at: t0.addingTimeInterval(3))
        XCTAssertEqual(machine.state, .failed)

        // A stale/failed page must not be promoted to ready by a late media event. Recovery
        // requires an explicit load/recovery transition.
        machine.handle(
            .mediaObserved(hasVideo: true, isPlaying: true),
            at: t0.addingTimeInterval(4)
        )
        XCTAssertEqual(machine.state, .failed)

        machine.handle(.recoveryStarted, at: t0.addingTimeInterval(5))
        XCTAssertEqual(machine.state, .reconnecting)
        machine.handle(
            .mediaObserved(hasVideo: true, isPlaying: true),
            at: t0.addingTimeInterval(6)
        )
        XCTAssertEqual(machine.state, .ready)
    }

    func testPipFailureDoesNotProduceUnsupportedState() {
        loadAndPlay()
        machine.handle(.pipRequested)
        machine.handle(.pipFailed("platformUnsupported"))
        XCTAssertNotEqual(machine.state, .unsupported)
        XCTAssertEqual(machine.state, .ready)
        XCTAssertTrue(machine.hasLoadedPage)
    }
}
