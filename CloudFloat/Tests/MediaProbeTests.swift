import XCTest
@testable import CloudFloat

final class MediaProbeTests: XCTestCase {
    private let receivedAt = Date(timeIntervalSince1970: 1_700_000_100)

    private func snapshotWire(
        frameID: String = "frame-1",
        origin: String = "https://sr.mihoyo.com",
        isTopFrame: Bool = true,
        videoCount: Int = 1,
        videosJSON: String = """
        [{"index":0,"playing":true,"paused":false,"ended":false,"readyState":4,
          "networkState":2,"width":1920,"height":1080,"durationSeconds":null,
          "muted":false,"volume":1,"hasSrcObject":false,"srcKind":"network",
          "pipSupported":true,"presentationMode":"inline","inPiP":false,
          "drmProtected":false,"pipFeatureAllowed":true}]
        """,
        canvasCount: Int = 0,
        iframeCount: Int = 0
    ) -> MediaProbeWireMessage {
        let json = """
        {
          "type": "snapshot",
          "frameId": "\(frameID)",
          "origin": "\(origin)",
          "isTopFrame": \(isTopFrame),
          "visibilityState": "visible",
          "videoCount": \(videoCount),
          "videos": \(videosJSON),
          "canvasCount": \(canvasCount),
          "iframeCount": \(iframeCount),
          "documentPiPEnabled": true,
          "pipFeatureAllowed": true,
          "pageKind": "media",
          "reason": "install",
          "timestamp": 1700000000000
        }
        """
        return try! JSONDecoder().decode(MediaProbeWireMessage.self, from: Data(json.utf8))
    }

    private func canvasWire(frameID: String = "canvas-frame", iframeCount: Int = 0) -> MediaProbeWireMessage {
        let json = """
        {
          "type": "snapshot",
          "frameId": "\(frameID)",
          "origin": "http://127.0.0.1:8080",
          "isTopFrame": true,
          "visibilityState": "visible",
          "videoCount": 0,
          "videos": [],
          "canvasCount": 2,
          "iframeCount": \(iframeCount),
          "documentPiPEnabled": false,
          "pageKind": "canvas",
          "reason": "install",
          "timestamp": 1700000000000
        }
        """
        return try! JSONDecoder().decode(MediaProbeWireMessage.self, from: Data(json.utf8))
    }

    func testSnapshotDecodingAndOriginSanitisation() {
        let wire = snapshotWire(
            origin: "https://user:pass@sr.mihoyo.com/cloud/?token=secret#frag"
        )
        let snapshot = MediaFrameSnapshot(wire: wire, receivedAt: receivedAt)
        XCTAssertNotNil(snapshot)
        XCTAssertEqual(snapshot?.frameID, "frame-1")
        XCTAssertEqual(snapshot?.origin, "https://sr.mihoyo.com")
        XCTAssertFalse(snapshot?.origin.contains("token") ?? true)
        XCTAssertEqual(snapshot?.videoCount, 1)
        XCTAssertEqual(snapshot?.videos.count, 1)
        XCTAssertEqual(snapshot?.videos.first?.playing, true)
        XCTAssertEqual(snapshot?.videos.first?.readyState, 4)
        XCTAssertEqual(snapshot?.videos.first?.pipSupported, true)
        XCTAssertEqual(snapshot?.receivedAt, receivedAt)
    }

    func testSnapshotRequiresFrameIDAndSnapshotType() {
        let noFrame = snapshotWire(frameID: "")
        XCTAssertNil(MediaFrameSnapshot(wire: noFrame, receivedAt: receivedAt))

        let eventWire = MediaProbeWireMessage(
            type: "event",
            frameId: "frame-1",
            origin: "https://sr.mihoyo.com",
            isTopFrame: true,
            visibilityState: nil,
            videoCount: nil,
            videos: nil,
            canvasCount: nil,
            iframeCount: nil,
            documentPiPEnabled: nil,
            pipFeatureAllowed: nil,
            pageKind: nil,
            reason: nil,
            timestamp: nil,
            name: "playing",
            videoIndex: 0,
            readyState: 4,
            presentationMode: "inline",
            isPlaying: true,
            hasVideo: true,
            requestId: nil,
            ok: nil,
            method: nil,
            message: nil
        )
        XCTAssertNil(MediaFrameSnapshot(wire: eventWire, receivedAt: receivedAt))
    }

    func testAggregateClassifiesHTMLVideo() {
        let html = MediaFrameSnapshot(wire: snapshotWire(), receivedAt: receivedAt)!
        let canvas = MediaFrameSnapshot(
            wire: canvasWire(frameID: "canvas-frame", iframeCount: 1),
            receivedAt: receivedAt.addingTimeInterval(1)
        )!
        let frames = [html.frameID: html, canvas.frameID: canvas]
        let aggregate = MediaAggregate.make(from: frames)

        XCTAssertEqual(aggregate.frameCount, 2)
        XCTAssertEqual(aggregate.kind, .htmlVideo)
        XCTAssertEqual(aggregate.videoCount, 1)
        XCTAssertEqual(aggregate.playingVideoCount, 1)
        XCTAssertEqual(aggregate.piPCapablePlayingVideoCount, 1)
        XCTAssertTrue(aggregate.hasPiPCapablePlayingVideo)
        XCTAssertEqual(aggregate.canvasCount, 2)
        XCTAssertEqual(aggregate.iframeCount, 1)
        XCTAssertEqual(aggregate.origins.count, 2)
        XCTAssertTrue(aggregate.hasAnyVideo)
        XCTAssertTrue(aggregate.hasPlayingVideo)
        XCTAssertFalse(aggregate.isInPiP)
    }

    func testAggregateClassifiesWebRTCVideo() {
        let videos = """
        [{"index":0,"playing":true,"paused":false,"ended":false,"readyState":4,
          "networkState":2,"width":1280,"height":720,"durationSeconds":null,
          "muted":false,"volume":1,"hasSrcObject":true,"srcKind":"mediastream",
          "pipSupported":true,"presentationMode":"inline","inPiP":false,
          "drmProtected":false,"pipFeatureAllowed":true}]
        """
        let wire = snapshotWire(videosJSON: videos)
        let snapshot = MediaFrameSnapshot(wire: wire, receivedAt: receivedAt)!
        let aggregate = MediaAggregate.make(from: [snapshot.frameID: snapshot])
        XCTAssertEqual(aggregate.kind, .webRTCVideo)
        XCTAssertEqual(aggregate.bestVideo?.srcKind, "mediastream")
    }

    func testAggregateClassifiesCanvasAndCrossOriginFrameAndUnknown() {
        let canvas = MediaFrameSnapshot(wire: canvasWire(), receivedAt: receivedAt)!
        XCTAssertEqual(MediaAggregate.make(from: [canvas.frameID: canvas]).kind, .canvas)

        let iframeJSON = """
        {
          "type": "snapshot", "frameId": "iframe-frame", "origin": "https://example.com",
          "isTopFrame": true, "visibilityState": "visible", "videoCount": 0, "videos": [],
          "canvasCount": 0, "iframeCount": 2, "documentPiPEnabled": false,
          "pageKind": "nested", "timestamp": 1700000000000
        }
        """
        let iframeWire = try! JSONDecoder().decode(
            MediaProbeWireMessage.self,
            from: Data(iframeJSON.utf8)
        )
        let iframe = MediaFrameSnapshot(wire: iframeWire, receivedAt: receivedAt)!
        XCTAssertEqual(MediaAggregate.make(from: [iframe.frameID: iframe]).kind, .crossOriginFrame)
        XCTAssertEqual(MediaAggregate.make(from: [:]).kind, .unknown)
    }

    func testAggregateCountsPlayingAndPiPAfterEnteringPip() {
        let videos = """
        [{"index":0,"playing":true,"paused":false,"ended":false,"readyState":4,
          "networkState":2,"width":1920,"height":1080,"durationSeconds":12.5,
          "muted":false,"volume":1,"hasSrcObject":false,"srcKind":"network",
          "pipSupported":true,"presentationMode":"picture-in-picture","inPiP":true,
          "drmProtected":false,"pipFeatureAllowed":true}]
        """
        let snapshot = MediaFrameSnapshot(
            wire: snapshotWire(videosJSON: videos),
            receivedAt: receivedAt
        )!
        let aggregate = MediaAggregate.make(from: [snapshot.frameID: snapshot])
        XCTAssertTrue(aggregate.isInPiP)
        XCTAssertEqual(aggregate.bestVideo?.durationSeconds, 12.5)
        XCTAssertEqual(aggregate.bestVideo?.inPiP, true)
    }

    func testSnapshotClampsUntrustedValues() {
        let videos = """
        [{"index":0,"playing":false,"readyState":99,"networkState":99,
          "width":999999,"height":-4,"durationSeconds":-3,"volume":9,
          "pipSupported":false,"drmProtected":false}]
        """
        let wire = snapshotWire(videoCount: 100_000, videosJSON: videos, canvasCount: 50_000)
        let snapshot = MediaFrameSnapshot(wire: wire, receivedAt: receivedAt)!
        XCTAssertEqual(snapshot.videoCount, 9_999)
        XCTAssertEqual(snapshot.canvasCount, 9_999)
        XCTAssertEqual(snapshot.videos.first?.readyState, 4)
        XCTAssertEqual(snapshot.videos.first?.networkState, 3)
        XCTAssertEqual(snapshot.videos.first?.width, 32_768)
        XCTAssertEqual(snapshot.videos.first?.height, 0)
        XCTAssertNil(snapshot.videos.first?.durationSeconds)
        XCTAssertEqual(snapshot.videos.first?.volume, 1)
    }

    func testPlaybackEventDecodingAndPipActive() {
        let json = """
        {
          "type": "event", "frameId": "frame-1", "origin": "https://sr.mihoyo.com",
          "isTopFrame": true, "name": "enterpictureinpicture", "videoIndex": 0,
          "readyState": 4, "presentationMode": "picture-in-picture",
          "isPlaying": true, "hasVideo": true, "reason": "webkitpresentationmodechanged",
          "timestamp": 1700000000000
        }
        """
        let wire = try! JSONDecoder().decode(MediaProbeWireMessage.self, from: Data(json.utf8))
        let event = MediaPlaybackEvent(wire: wire, receivedAt: receivedAt)
        XCTAssertNotNil(event)
        XCTAssertEqual(event?.name, .enterpictureinpicture)
        XCTAssertTrue(event?.isPiPActive == true)
        XCTAssertEqual(event?.videoIndex, 0)
        XCTAssertEqual(event?.origin, "https://sr.mihoyo.com")
        XCTAssertEqual(event?.source, "webkitpresentationmodechanged")
    }

    func testUnknownPlaybackEventIsIgnored() {
        let json = """
        {"type":"event","frameId":"f","origin":"https://example.com","name":"unknown-event"}
        """
        let wire = try! JSONDecoder().decode(MediaProbeWireMessage.self, from: Data(json.utf8))
        XCTAssertNil(MediaPlaybackEvent(wire: wire, receivedAt: receivedAt))
    }

    func testPiPFailureReasonMapping() {
        XCTAssertEqual(PiPFailureReason.map(jsReason: "noVideo"), .noVideo)
        XCTAssertEqual(PiPFailureReason.map(jsReason: "notPlaying"), .videoNotPlaying)
        XCTAssertEqual(PiPFailureReason.map(jsReason: "notSupported"), .pageDoesNotSupportPiP)
        XCTAssertEqual(
            PiPFailureReason.map(jsReason: "promiseRejected:NotSupportedError"),
            .pageDoesNotSupportPiP
        )
        XCTAssertEqual(PiPFailureReason.map(jsReason: "NotAllowedError"), .requiresUserGesture)
        XCTAssertEqual(
            PiPFailureReason.map(jsReason: "promiseRejected:NotAllowedError"),
            .requiresUserGesture
        )
        XCTAssertEqual(
            PiPFailureReason.map(jsReason: "presentationModeNotApplied"),
            .requiresUserGesture
        )
        XCTAssertEqual(
            PiPFailureReason.map(jsReason: "featurePolicyDenied"),
            .featurePolicyDenied
        )
        XCTAssertEqual(
            PiPFailureReason.map(jsReason: "promiseRejected:InvalidStateError"),
            .fullscreenOrCasting
        )
        XCTAssertEqual(PiPFailureReason.map(jsReason: nil), .unknown)
        XCTAssertEqual(PiPFailureReason.map(jsReason: "wat"), .unknown)
        for reason in PiPFailureReason.allCases {
            XCTAssertFalse(reason.userMessage.isEmpty)
        }
    }

    func testProbeScriptResourceIsBundledWithRequiredHooks() throws {
        guard let url = Bundle.main.url(forResource: "MediaProbe", withExtension: "js") else {
            XCTFail("MediaProbe.js is missing from the app bundle")
            return
        }
        let source = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(source.contains("__cloudFloatProbe"))
        XCTAssertTrue(source.contains("__CF_BUTTON_ENABLED__"))
        XCTAssertTrue(source.contains("requestPictureInPicture"))
        XCTAssertTrue(source.contains("webkitSetPresentationMode"))
        XCTAssertTrue(source.contains("cloudFloatMedia"))
        XCTAssertTrue(source.contains("enterpictureinpicture"))
        XCTAssertTrue(source.contains("MutationObserver"))
        XCTAssertTrue(source.contains("frameId"))
        // The payload must not carry full media URLs.
        XCTAssertFalse(source.contains("currentSrc: video.currentSrc"))
        XCTAssertFalse(source.contains("url: video.currentSrc"))
    }

    func testMainFramePiPCapabilityRequiresVideoInTopFrame() {
        let topVideo = MediaFrameSnapshot(wire: snapshotWire(), receivedAt: receivedAt)!
        let topAggregate = MediaAggregate.make(from: [topVideo.frameID: topVideo])
        XCTAssertTrue(topAggregate.mainFrameHasPiPCapablePlayingVideo)

        let childOnly = MediaFrameSnapshot(
            wire: snapshotWire(frameID: "child-frame", isTopFrame: false),
            receivedAt: receivedAt
        )!
        let childAggregate = MediaAggregate.make(from: [childOnly.frameID: childOnly])
        XCTAssertTrue(childAggregate.hasPiPCapablePlayingVideo)
        XCTAssertFalse(childAggregate.mainFrameHasPiPCapablePlayingVideo)

        let topNoVideo = MediaFrameSnapshot(
            wire: canvasWire(frameID: "top-no-video", iframeCount: 1),
            receivedAt: receivedAt
        )!
        let mixed = MediaAggregate.make(from: [
            topNoVideo.frameID: topNoVideo,
            childOnly.frameID: childOnly
        ])
        XCTAssertTrue(mixed.hasPiPCapablePlayingVideo)
        XCTAssertFalse(mixed.mainFrameHasPiPCapablePlayingVideo)
    }

    func testSubframeOnlyPiPRequiresInPageControl() {
        let topVideo = MediaFrameSnapshot(wire: snapshotWire(), receivedAt: receivedAt)!
        let topAggregate = MediaAggregate.make(from: [topVideo.frameID: topVideo])
        XCTAssertFalse(WebPictureInPictureCoordinator.requiresInPageControl(for: topAggregate))

        let topNoVideo = MediaFrameSnapshot(
            wire: canvasWire(frameID: "top-no-video", iframeCount: 1),
            receivedAt: receivedAt
        )!
        let childVideo = MediaFrameSnapshot(
            wire: snapshotWire(frameID: "child-video", isTopFrame: false),
            receivedAt: receivedAt
        )!
        let mixed = MediaAggregate.make(from: [
            topNoVideo.frameID: topNoVideo,
            childVideo.frameID: childVideo
        ])
        XCTAssertTrue(mixed.hasPiPCapablePlayingVideo)
        XCTAssertTrue(WebPictureInPictureCoordinator.requiresInPageControl(for: mixed))
    }

    func testMediaKindCapabilityFlags() {
        XCTAssertTrue(MediaKind.htmlVideo.canUseHTML5PiP)
        XCTAssertTrue(MediaKind.webRTCVideo.canUseHTML5PiP)
        XCTAssertFalse(MediaKind.canvas.canUseHTML5PiP)
        XCTAssertFalse(MediaKind.crossOriginFrame.canUseHTML5PiP)
        XCTAssertFalse(MediaKind.unknown.canUseHTML5PiP)
    }
}
