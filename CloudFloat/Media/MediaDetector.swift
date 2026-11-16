import Foundation
import WebKit

/// Owns the per-frame media probe bridge and aggregates observations.
///
/// Privacy: frame origins are reduced to `scheme://host`; video URLs, page paths, cookies
/// and tokens never leave the page. All observation is event-driven, with a low-frequency
/// foreground-only refresh as a safety net.
@MainActor
final class MediaDetector: NSObject, ObservableObject {
    static let messageHandlerName = "cloudFloatMedia"
    static let userScriptName = "CloudFloatMediaProbe"

    @Published private(set) var frames: [String: MediaFrameSnapshot] = [:]
    @Published private(set) var aggregate: MediaAggregate = .empty
    @Published private(set) var lastSnapshotReceivedAt: Date?
    @Published private(set) var lastPlaybackEvent: MediaPlaybackEvent?
    @Published private(set) var lastProbeError: String?
    @Published private(set) var probeScriptLoaded = false
    @Published private(set) var isPolling = false

    var onSnapshot: ((MediaAggregate, MediaFrameSnapshot) -> Void)?
    var onEvent: ((MediaPlaybackEvent) -> Void)?
    var onProbeError: ((String) -> Void)?

    private weak var webView: WKWebView?
    private let userContentController: WKUserContentController
    private var probeSource: String?
    private var pollTimer: Timer?
    private var inPageControlEnabled: Bool
    private let now: () -> Date

    private struct PendingPiPRequest {
        let continuation: CheckedContinuation<PiPRequestOutcome, Never>
        let createdAt: Date
    }

    private var pendingPiPRequests: [String: PendingPiPRequest] = [:]

    init(
        configuration: WKWebViewConfiguration,
        inPageControlEnabled: Bool = true,
        now: @escaping () -> Date = Date.init
    ) {
        self.userContentController = configuration.userContentController
        self.inPageControlEnabled = inPageControlEnabled
        self.now = now
        super.init()

        userContentController.add(self, name: Self.messageHandlerName)
        loadProbeSource()
        installUserScript()
    }

    deinit {
        // The WKUserContentController retains this handler; app-lifetime ownership means
        // normal deallocation requires an explicit `shutdown()`.
    }

    // MARK: - Lifecycle

    func attach(webView: WKWebView) {
        self.webView = webView
    }

    func shutdown() {
        stopPolling()
        let requestIDs = Array(pendingPiPRequests.keys)
        for requestID in requestIDs {
            pendingPiPRequests.removeValue(forKey: requestID)?.continuation.resume(
                returning: .failure(reason: .probeUnavailable, detail: "detector shutdown")
            )
        }
        userContentController.removeScriptMessageHandler(forName: Self.messageHandlerName)
        userContentController.removeAllUserScripts()
        webView = nil
    }

    func clearFrames(reason: String) {
        frames.removeAll()
        aggregate = .empty
        lastSnapshotReceivedAt = nil
        lastPlaybackEvent = nil
        lastProbeError = nil
        _ = reason // Reason is logged by BrowserSession/AppCoordinator; kept for call-site clarity.
    }

    /// Applies the in-page control preference. Existing subframes keep their injected copy
    /// until they navigate; the main frame is updated immediately.
    func setInPageControlEnabled(_ enabled: Bool) {
        guard enabled != inPageControlEnabled else { return }
        inPageControlEnabled = enabled
        installUserScript()
        evaluate(
            "window.__cloudFloatProbe && window.__cloudFloatProbe.setButtonEnabled(\(enabled ? "true" : "false"));"
        )
    }

    var inPageControlCurrentlyEnabled: Bool { inPageControlEnabled }

    // MARK: - Foreground polling

    func startPolling() {
        guard FeatureFlags.jsMediaProbeEnabled else { return }
        guard pollTimer == nil else { return }
        let timer = Timer(timeInterval: FeatureFlags.foregroundProbePollInterval, repeats: true) {
            [weak self] _ in
            Task { @MainActor in
                self?.refreshNow()
            }
        }
        timer.tolerance = 1.0
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
        isPolling = true
        refreshNow()
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
        isPolling = false
    }

    func refreshNow() {
        guard webView != nil else { return }
        evaluate("window.__cloudFloatProbe && window.__cloudFloatProbe.refresh();")
    }

    // MARK: - PiP controls

    /// Requests HTML5 PiP from the main frame. `evaluateJavaScript` usually lacks the
    /// transient activation WebKit requires, so a `.requiresUserGesture` failure is an
    /// expected outcome, not a bug. The UI then points the user at the in-page control.
    func requestPiP(videoIndex: Int? = nil) async -> PiPRequestOutcome {
        guard let webView else {
            return .failure(reason: .probeUnavailable, detail: "no web view")
        }
        guard probeScriptLoaded else {
            return .failure(reason: .probeUnavailable, detail: "probe script missing")
        }
        let requestID = UUID().uuidString
        let indexLiteral = videoIndex.map(String.init) ?? "null"
        let script = """
        window.__cloudFloatProbe ? window.__cloudFloatProbe.requestPiP('\(requestID)', \(indexLiteral)) : null;
        """

        return await withCheckedContinuation { continuation in
            pendingPiPRequests[requestID] = PendingPiPRequest(
                continuation: continuation,
                createdAt: now()
            )
            webView.evaluateJavaScript(script) { [weak self] _, error in
                guard let error else { return }
                Task { @MainActor in
                    self?.resolvePiP(
                        requestID,
                        .failure(reason: .probeUnavailable, detail: error.localizedDescription)
                    )
                }
            }
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                self?.resolvePiP(requestID, .failure(reason: .timeout, detail: nil))
            }
        }
    }

    func showInPagePiPControl() -> Bool {
        evaluate("window.__cloudFloatProbe && window.__cloudFloatProbe.showPiPButton();")
        return true
    }

    func hideInPagePiPControl() {
        evaluate("window.__cloudFloatProbe && window.__cloudFloatProbe.hidePiPButton();")
    }

    func exitPiP() {
        evaluate("window.__cloudFloatProbe && window.__cloudFloatProbe.exitPiP();")
    }

    // MARK: - Script plumbing

    private func loadProbeSource() {
        let bundles = [Bundle.main, Bundle(for: MediaDetector.self)]
        for bundle in bundles {
            let candidates: [URL?] = [
                bundle.url(forResource: "MediaProbe", withExtension: "js"),
                bundle.url(forResource: "MediaProbe", withExtension: "js", subdirectory: "Media")
            ]
            for candidate in candidates {
                guard let url = candidate, let source = try? String(contentsOf: url, encoding: .utf8) else {
                    continue
                }
                probeSource = source
                probeScriptLoaded = true
                return
            }
        }
        probeScriptLoaded = false
        lastProbeError = "MediaProbe.js 未打包进 App Bundle"
    }

    private func installUserScript() {
        guard FeatureFlags.jsMediaProbeEnabled, let source = probeSource else { return }
        let enabledLiteral = inPageControlEnabled ? "true" : "false"
        let script = source.replacingOccurrences(of: "__CF_BUTTON_ENABLED__", with: enabledLiteral)
        userContentController.removeAllUserScripts()
        userContentController.addUserScript(
            WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        )
    }

    private func evaluate(_ script: String) {
        guard let webView else { return }
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    private func resolvePiP(_ requestID: String, _ outcome: PiPRequestOutcome) {
        guard let pending = pendingPiPRequests.removeValue(forKey: requestID) else { return }
        pending.continuation.resume(returning: outcome)
    }

    // MARK: - Message handling

    private func decode(_ body: Any) -> MediaProbeWireMessage? {
        guard let dictionary = body as? [String: Any] else {
            lastProbeError = "探测消息不是字典"
            return nil
        }
        guard JSONSerialization.isValidJSONObject(dictionary) else {
            lastProbeError = "探测消息包含不可序列化内容"
            return nil
        }
        let data: Data
        do {
            data = try JSONSerialization.data(withJSONObject: dictionary, options: [])
        } catch {
            lastProbeError = "探测消息序列化失败"
            return nil
        }
        guard data.count <= 128_000 else {
            lastProbeError = "探测消息过大，已忽略"
            return nil
        }
        do {
            return try JSONDecoder().decode(MediaProbeWireMessage.self, from: data)
        } catch {
            lastProbeError = "探测消息字段不合法"
            return nil
        }
    }

    private func handle(snapshot: MediaFrameSnapshot, receivedAt: Date) {
        frames[snapshot.frameID] = snapshot
        if frames.count > FeatureFlags.maxTrackedFrames {
            let overflow = frames.count - FeatureFlags.maxTrackedFrames
            let oldest = frames.values
                .sorted { $0.receivedAt < $1.receivedAt }
                .prefix(overflow)
                .map(\.frameID)
            for id in oldest {
                frames.removeValue(forKey: id)
            }
        }
        aggregate = MediaAggregate.make(from: frames)
        lastSnapshotReceivedAt = receivedAt
        onSnapshot?(aggregate, snapshot)
    }

    private func handle(event: MediaPlaybackEvent) {
        lastPlaybackEvent = event
        if event.name == .enterpictureinpicture {
            aggregate.isInPiP = true
        } else if event.name == .leavepictureinpicture {
            aggregate.isInPiP = false
        }
        onEvent?(event)
    }

    private func handlePiPResult(_ wire: MediaProbeWireMessage) {
        guard let requestID = wire.requestId else { return }
        let outcome: PiPRequestOutcome
        if wire.ok == true {
            outcome = .success(method: wire.method ?? "unknown")
        } else {
            let reason = PiPFailureReason.map(jsReason: wire.reason)
            let detail = wire.message ?? wire.reason
            outcome = .failure(reason: reason, detail: detail)
        }
        resolvePiP(requestID, outcome)
    }

    var diagnosticsMetadata: [String: String] {
        [
            "frames": String(aggregate.frameCount),
            "videos": String(aggregate.videoCount),
            "playing": String(aggregate.playingVideoCount),
            "pipCapablePlaying": String(aggregate.piPCapablePlayingVideoCount),
            "canvases": String(aggregate.canvasCount),
            "iframes": String(aggregate.iframeCount),
            "kind": aggregate.kind.rawValue,
            "origins": aggregate.origins.joined(separator: ",")
        ]
    }
}

// MARK: - WKScriptMessageHandler

extension MediaDetector: WKScriptMessageHandler {
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == Self.messageHandlerName else { return }
        let receivedAt = now()
        guard let wire = decode(message.body) else { return }

        switch wire.type {
        case "snapshot":
            guard let snapshot = MediaFrameSnapshot(wire: wire, receivedAt: receivedAt) else {
                lastProbeError = "快照缺少 frameId"
                return
            }
            handle(snapshot: snapshot, receivedAt: receivedAt)
        case "event":
            guard let event = MediaPlaybackEvent(wire: wire, receivedAt: receivedAt) else {
                lastProbeError = "未知的媒体事件"
                return
            }
            handle(event: event)
        case "pipResult":
            handlePiPResult(wire)
        case "probeError":
            let message = PrivacyRedactor.redact(String((wire.message ?? "页面探测错误").prefix(200)))
            lastProbeError = message
            onProbeError?(message)
        default:
            break
        }
    }
}
