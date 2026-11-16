import AVKit
import WebKit
import XCTest
@testable import CloudFloat

@MainActor
final class WebPictureInPictureTests: XCTestCase {
    func testNativeMediaPipelineIsExplicitlyNotFeasible() async {
        let coordinator = NativePictureInPictureCoordinator()
        XCTAssertFalse(NativePictureInPictureCoordinator.isFeatureEnabled)
        XCTAssertFalse(coordinator.isAvailable)
        if case .notFeasible(let reason) = NativePictureInPictureCoordinator.status {
            XCTAssertTrue(reason.contains("Not Feasible"))
        } else {
            XCTFail("M4 must be marked Not Feasible")
        }

        do {
            try await coordinator.startNativePictureInPicture()
            XCTFail("Native pipeline must not start")
        } catch let error as NativeMediaPipelineError {
            guard case .notImplemented = error else {
                XCTFail("Unexpected native pipeline error: \(error)")
                return
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testPiPOutcomeHelpers() {
        XCTAssertTrue(PiPRequestOutcome.success(method: "presentationMode").isSuccess)
        XCTAssertNil(PiPRequestOutcome.success(method: "presentationMode").failureReason)

        let failure = PiPRequestOutcome.failure(
            reason: .requiresUserGesture,
            detail: "not enough activation"
        )
        XCTAssertFalse(failure.isSuccess)
        XCTAssertEqual(failure.failureReason, .requiresUserGesture)
    }

    func testAvailabilityFailsClosedWithoutPlatformSupport() async throws {
        let configuration = WKWebViewConfiguration()
        let detector = MediaDetector(configuration: configuration)
        defer { detector.shutdown() }

        let coordinator = WebPictureInPictureCoordinator(
            mediaDetector: detector,
            configurationAllowsPiP: { true },
            platformSupportsPiP: { false }
        )
        XCTAssertFalse(coordinator.platformSupportsPiP)
        XCTAssertFalse(coordinator.availability.isAvailable)
        XCTAssertEqual(coordinator.availability.reason, .platformUnsupported)

        let outcome = await coordinator.requestPiP()
        XCTAssertEqual(outcome.failureReason, .platformUnsupported)
        XCTAssertEqual(coordinator.state, .unavailable(.platformUnsupported))
    }

    func testConfigurationGateIsReported() {
        let configuration = WKWebViewConfiguration()
        let detector = MediaDetector(configuration: configuration)
        defer { detector.shutdown() }
        let coordinator = WebPictureInPictureCoordinator(
            mediaDetector: detector,
            configurationAllowsPiP: { false },
            platformSupportsPiP: { true }
        )
        XCTAssertFalse(coordinator.availability.isAvailable)
        XCTAssertEqual(coordinator.availability.reason, .webViewConfigurationDisabled)
    }

    func testMissingProbeSnapshotReportsProbeUnavailable() {
        let configuration = WKWebViewConfiguration()
        let detector = MediaDetector(configuration: configuration)
        defer { detector.shutdown() }
        let coordinator = WebPictureInPictureCoordinator(
            mediaDetector: detector,
            configurationAllowsPiP: { true },
            platformSupportsPiP: { true }
        )
        XCTAssertFalse(coordinator.availability.isAvailable)
        XCTAssertEqual(coordinator.availability.reason, .probeUnavailable)
    }

    func testEnterAndLeaveEventsDriveCoordinatorState() {
        let configuration = WKWebViewConfiguration()
        let detector = MediaDetector(configuration: configuration)
        defer { detector.shutdown() }
        let coordinator = WebPictureInPictureCoordinator(
            mediaDetector: detector,
            configurationAllowsPiP: { true }
        )

        let enter = makeEvent(name: .enterpictureinpicture, mode: "picture-in-picture")
        coordinator.handle(event: enter)
        XCTAssertEqual(coordinator.state, .active)
        XCTAssertTrue(coordinator.isActive)

        let leave = makeEvent(name: .leavepictureinpicture, mode: "inline")
        coordinator.handle(event: leave)
        XCTAssertEqual(coordinator.state, .available)
        XCTAssertFalse(coordinator.isActive)
    }

    private func makeEvent(
        name: MediaPlaybackEvent.Name,
        mode: String
    ) -> MediaPlaybackEvent {
        let json = """
        {
          "type": "event", "frameId": "frame-1", "origin": "https://sr.mihoyo.com",
          "isTopFrame": true, "name": "\(name.rawValue)", "videoIndex": 0,
          "readyState": 4, "presentationMode": "\(mode)", "isPlaying": true,
          "hasVideo": true, "timestamp": 1700000000000
        }
        """
        let wire = try! JSONDecoder().decode(MediaProbeWireMessage.self, from: Data(json.utf8))
        return MediaPlaybackEvent(wire: wire, receivedAt: Date())!
    }
}
