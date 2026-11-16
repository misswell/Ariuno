import Foundation

// MARK: - Media kind

/// High-level classification of what the page appears to use for rendering the game.
/// This is an observation from the (per-frame) probe, not a guarantee that PiP is possible.
enum MediaKind: String, Codable, CaseIterable {
    case htmlVideo
    case webRTCVideo
    case canvas
    case crossOriginFrame
    case unknown

    var displayName: String {
        switch self {
        case .htmlVideo: return "HTML5 视频"
        case .webRTCVideo: return "WebRTC 视频（MediaStream）"
        case .canvas: return "Canvas / WebGL"
        case .crossOriginFrame: return "跨域 iframe（DOM 不可访问）"
        case .unknown: return "未知/受保护渲染"
        }
    }

    var canUseHTML5PiP: Bool {
        self == .htmlVideo || self == .webRTCVideo
    }
}

// MARK: - Wire types sent by MediaProbe.js

struct MediaProbeWireVideo: Decodable, Equatable {
    let index: Int?
    let playing: Bool?
    let paused: Bool?
    let ended: Bool?
    let readyState: Int?
    let networkState: Int?
    let width: Int?
    let height: Int?
    let durationSeconds: Double?
    let muted: Bool?
    let volume: Double?
    let hasSrcObject: Bool?
    let srcKind: String?
    let pipSupported: Bool?
    let presentationMode: String?
    let inPiP: Bool?
    let drmProtected: Bool?
    let pipFeatureAllowed: Bool?
}

struct MediaProbeWireMessage: Decodable, Equatable {
    let type: String
    let frameId: String?
    let origin: String?
    let isTopFrame: Bool?
    let visibilityState: String?
    let videoCount: Int?
    let videos: [MediaProbeWireVideo]?
    let canvasCount: Int?
    let iframeCount: Int?
    let documentPiPEnabled: Bool?
    let pipFeatureAllowed: Bool?
    let pageKind: String?
    let reason: String?
    let timestamp: Double?

    // Event payload
    let name: String?
    let videoIndex: Int?
    let readyState: Int?
    let presentationMode: String?
    let isPlaying: Bool?
    let hasVideo: Bool?

    // PiP result payload
    let requestId: String?
    let ok: Bool?
    let method: String?
    let message: String?
}

// MARK: - Native media state

struct MediaVideoState: Codable, Equatable, Identifiable {
    let index: Int
    let playing: Bool
    let paused: Bool
    let ended: Bool
    let readyState: Int
    let networkState: Int
    let width: Int
    let height: Int
    let durationSeconds: Double?
    let muted: Bool
    let volume: Double
    let hasSrcObject: Bool
    let srcKind: String
    let pipSupported: Bool
    let presentationMode: String?
    let inPiP: Bool
    let drmProtected: Bool
    let pipFeatureAllowed: Bool?

    var id: Int { index }

    var resolutionDescription: String {
        guard width > 0, height > 0 else { return "无尺寸" }
        return "\(width)×\(height)"
    }

    var playbackStateDescription: String {
        if playing { return "播放中" }
        if ended { return "已结束" }
        if paused { return "已暂停" }
        return "未播放"
    }

    init(wire: MediaProbeWireVideo, fallbackIndex: Int) {
        self.index = wire.index ?? fallbackIndex
        self.playing = wire.playing ?? false
        self.paused = wire.paused ?? true
        self.ended = wire.ended ?? false
        self.readyState = min(max(wire.readyState ?? 0, 0), 4)
        self.networkState = min(max(wire.networkState ?? 0, 0), 3)
        self.width = min(max(wire.width ?? 0, 0), 32_768)
        self.height = min(max(wire.height ?? 0, 0), 32_768)
        if let duration = wire.durationSeconds, duration.isFinite, duration >= 0 {
            self.durationSeconds = min(duration, 24 * 60 * 60)
        } else {
            self.durationSeconds = nil
        }
        self.muted = wire.muted ?? false
        self.volume = min(max(wire.volume ?? 0, 0), 1)
        self.hasSrcObject = wire.hasSrcObject ?? false
        self.srcKind = String((wire.srcKind ?? "unknown").prefix(32))
        self.pipSupported = wire.pipSupported ?? false
        self.presentationMode = wire.presentationMode.map { String($0.prefix(32)) }
        self.inPiP = wire.inPiP ?? false
        self.drmProtected = wire.drmProtected ?? false
        self.pipFeatureAllowed = wire.pipFeatureAllowed
    }
}

struct MediaFrameSnapshot: Codable, Equatable, Identifiable {
    let frameID: String
    let origin: String
    let isTopFrame: Bool
    let visibilityState: String
    let videoCount: Int
    let videos: [MediaVideoState]
    let canvasCount: Int
    let iframeCount: Int
    let documentPiPEnabled: Bool
    let pipFeatureAllowed: Bool?
    let pageKind: String
    let probeReason: String
    let receivedAt: Date

    var id: String { frameID }

    var hasPlayingVideo: Bool { videos.contains(where: \.playing) }

    var bestVideo: MediaVideoState? {
        videos.first(where: { $0.playing && $0.pipSupported })
            ?? videos.first(where: \.playing)
            ?? videos.first(where: \.pipSupported)
            ?? videos.first
    }

    init?(wire: MediaProbeWireMessage, receivedAt: Date) {
        guard wire.type == "snapshot" else { return nil }
        let rawFrameID = wire.frameId ?? ""
        let safeFrameID = rawFrameID.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        guard !safeFrameID.isEmpty else { return nil }

        self.frameID = String(safeFrameID.prefix(64))
        self.origin = MediaFrameSnapshot.sanitizedOrigin(wire.origin)
        self.isTopFrame = wire.isTopFrame ?? false
        self.visibilityState = String((wire.visibilityState ?? "unknown").prefix(24))
        self.videoCount = min(max(wire.videoCount ?? 0, 0), 9_999)
        self.videos = (wire.videos ?? [])
            .prefix(FeatureFlags.maxVideosPerFrame)
            .enumerated()
            .map { MediaVideoState(wire: $1, fallbackIndex: $0) }
        self.canvasCount = min(max(wire.canvasCount ?? 0, 0), 9_999)
        self.iframeCount = min(max(wire.iframeCount ?? 0, 0), 9_999)
        self.documentPiPEnabled = wire.documentPiPEnabled ?? false
        self.pipFeatureAllowed = wire.pipFeatureAllowed
        self.pageKind = String((wire.pageKind ?? "unknown").prefix(24))
        self.probeReason = String((wire.reason ?? "unknown").prefix(48))
        self.receivedAt = receivedAt
    }

    /// Reduces any page-provided string to `scheme://host` so paths and tokens can never
    /// reach diagnostics through a malicious or buggy page.
    static func sanitizedOrigin(_ raw: String?) -> String {
        guard let raw, let url = URL(string: raw), let scheme = url.scheme?.lowercased() else {
            return "opaque"
        }
        guard scheme == "http" || scheme == "https" else { return "opaque" }
        guard let host = url.host, !host.isEmpty else { return "opaque" }
        let port = url.port.map { ":\($0)" } ?? ""
        return "\(scheme)://\(host)\(port)"
    }
}

// MARK: - Playback events

struct MediaPlaybackEvent: Equatable {
    enum Name: String, CaseIterable {
        case playing
        case pause
        case waiting
        case stalled
        case emptied
        case error
        case loadedmetadata
        case loadeddata
        case enterpictureinpicture
        case leavepictureinpicture
        case presentationmodechanged
        case visibilitychange
        case domchanged

        var isPiPTransition: Bool {
            self == .enterpictureinpicture || self == .leavepictureinpicture
        }

        var isPlaybackStop: Bool {
            self == .pause || self == .waiting || self == .stalled || self == .emptied || self == .error
        }
    }

    let name: Name
    let frameID: String
    let origin: String
    let isTopFrame: Bool
    let videoIndex: Int?
    let readyState: Int?
    let presentationMode: String?
    let isPlaying: Bool?
    let hasVideo: Bool
    let timestamp: Date
    let source: String

    var isPiPActive: Bool {
        if name == .enterpictureinpicture { return true }
        if name == .leavepictureinpicture { return false }
        return presentationMode == "picture-in-picture"
    }

    init?(wire: MediaProbeWireMessage, receivedAt: Date) {
        guard wire.type == "event", let rawName = wire.name, let name = Name(rawValue: rawName) else {
            return nil
        }
        let safeFrameID = (wire.frameId ?? "").filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        self.name = name
        self.frameID = String(safeFrameID.prefix(64))
        self.origin = MediaFrameSnapshot.sanitizedOrigin(wire.origin)
        self.isTopFrame = wire.isTopFrame ?? false
        self.videoIndex = wire.videoIndex
        self.readyState = wire.readyState.map { min(max($0, 0), 4) }
        self.presentationMode = wire.presentationMode.map { String($0.prefix(32)) }
        self.isPlaying = wire.isPlaying
        self.hasVideo = wire.hasVideo ?? false
        // Prefer page time (Date.now) for ordering, but never trust it beyond a sane window.
        if let ms = wire.timestamp, ms > 0 {
            let pageDate = Date(timeIntervalSince1970: ms / 1_000)
            if abs(pageDate.timeIntervalSince(receivedAt)) < 300 {
                self.timestamp = pageDate
            } else {
                self.timestamp = receivedAt
            }
        } else {
            self.timestamp = receivedAt
        }
        self.source = String((wire.reason ?? "event").prefix(48))
    }
}

// MARK: - Aggregate state used by UI and state machine

struct MediaAggregate: Equatable {
    var frameCount: Int = 0
    var videoCount: Int = 0
    var playingVideoCount: Int = 0
    var piPCapablePlayingVideoCount: Int = 0
    var canvasCount: Int = 0
    var iframeCount: Int = 0
    var kind: MediaKind = .unknown
    var origins: [String] = []
    var lastSnapshotAt: Date?
    var topFrame: MediaFrameSnapshot?
    var bestVideo: MediaVideoState?
    var isInPiP: Bool = false
    var anyPiPVideo: Bool { videosContainPiP }

    private var videosContainPiP: Bool = false

    var hasAnyVideo: Bool { videoCount > 0 }
    var hasPlayingVideo: Bool { playingVideoCount > 0 }
    var hasPiPCapablePlayingVideo: Bool { piPCapablePlayingVideoCount > 0 }

    /// Whether the native layer can call `requestPictureInPicture` directly. WKWebView's
    /// `evaluateJavaScript` only targets the main frame, so a video inside a cross-origin
    /// subframe must use its own in-page control instead.
    var mainFrameHasPiPCapablePlayingVideo: Bool {
        guard let topFrame, topFrame.isTopFrame else { return false }
        return topFrame.videos.contains { $0.playing && $0.pipSupported }
    }

    static let empty = MediaAggregate()

    static func make(from frames: [String: MediaFrameSnapshot]) -> MediaAggregate {
        var aggregate = MediaAggregate()
        guard !frames.isEmpty else { return aggregate }

        let snapshots = frames.values.sorted { $0.receivedAt < $1.receivedAt }
        aggregate.frameCount = snapshots.count
        aggregate.lastSnapshotAt = snapshots.last?.receivedAt
        aggregate.topFrame = snapshots.last(where: \.isTopFrame) ?? snapshots.last
        aggregate.origins = Array(Set(snapshots.map(\.origin))).sorted()

        var allVideos: [MediaVideoState] = []
        for snapshot in snapshots {
            aggregate.videoCount += snapshot.videoCount
            aggregate.canvasCount += snapshot.canvasCount
            aggregate.iframeCount += snapshot.iframeCount
            allVideos.append(contentsOf: snapshot.videos)
        }

        aggregate.playingVideoCount = allVideos.filter(\.playing).count
        aggregate.piPCapablePlayingVideoCount = allVideos.filter { $0.playing && $0.pipSupported }.count
        aggregate.videosContainPiP = allVideos.contains(where: \.pipSupported)
        aggregate.isInPiP = allVideos.contains(where: \.inPiP)
        aggregate.bestVideo = allVideos.first(where: { $0.playing && $0.pipSupported })
            ?? allVideos.first(where: \.playing)
            ?? allVideos.first(where: \.pipSupported)
            ?? allVideos.first

        if allVideos.contains(where: { $0.hasSrcObject || $0.srcKind == "mediastream" }) {
            aggregate.kind = .webRTCVideo
        } else if !allVideos.isEmpty {
            aggregate.kind = .htmlVideo
        } else if aggregate.canvasCount > 0 {
            aggregate.kind = .canvas
        } else if aggregate.iframeCount > 0 {
            aggregate.kind = .crossOriginFrame
        } else {
            aggregate.kind = .unknown
        }
        return aggregate
    }

    var summaryText: String {
        switch kind {
        case .htmlVideo, .webRTCVideo:
            return "\(videoCount) 个视频节点，\(playingVideoCount) 个播放中"
        case .canvas:
            return "检测到 \(canvasCount) 个 Canvas，未发现 HTML 视频"
        case .crossOriginFrame:
            return "\(iframeCount) 个 iframe，尚未在子 frame 中发现可访问视频"
        case .unknown:
            return "尚未发现可识别的媒体节点"
        }
    }
}

// MARK: - PiP results / failures

enum PiPFailureReason: String, Codable, CaseIterable, Equatable {
    case platformUnsupported
    case webViewConfigurationDisabled
    case noVideo
    case videoNotPlaying
    case pageDoesNotSupportPiP
    case notAllowed
    case requiresUserGesture
    case featurePolicyDenied
    case fullscreenOrCasting
    case probeUnavailable
    case timeout
    case unknown

    var userMessage: String {
        switch self {
        case .platformUnsupported:
            return "当前设备或系统不支持画中画（模拟器通常不支持）"
        case .webViewConfigurationDisabled:
            return "WebView 未启用画中画播放"
        case .noVideo:
            return "页面中没有可用的视频节点"
        case .videoNotPlaying:
            return "视频尚未播放，请先让游戏画面开始播放"
        case .pageDoesNotSupportPiP:
            return "网页或视频格式不支持系统画中画"
        case .notAllowed:
            return "系统或网页拒绝了画中画请求"
        case .requiresUserGesture:
            return "需要用户直接点击网页内的画中画按钮"
        case .featurePolicyDenied:
            return "跨域 iframe 的 Permissions Policy 禁止画中画"
        case .fullscreenOrCasting:
            return "全屏或其他投屏模式占用了视频"
        case .probeUnavailable:
            return "媒体探测脚本不可用，请重新加载页面"
        case .timeout:
            return "画中画请求超时，请重试或使用网页内按钮"
        case .unknown:
            return "未知的画中画错误，请查看诊断日志"
        }
    }

    /// Maps a JavaScript reason string into a typed failure. Keep this pure so it is easy to
    /// test and so native and JS error taxonomies stay aligned.
    static func map(jsReason: String?) -> PiPFailureReason {
        guard let reason = jsReason?.lowercased(), !reason.isEmpty else { return .unknown }
        switch reason {
        case "novideo": return .noVideo
        case "notplaying": return .videoNotPlaying
        case "notsupported", "promiserejected:notsupportederror", "notsupportederror":
            return .pageDoesNotSupportPiP
        case "notallowed", "promiserejected:notallowederror", "notallowederror":
            return .requiresUserGesture
        case "requiresusergesture", "promiserejected:securityerror", "securityerror":
            return .requiresUserGesture
        case "featuredisabled", "featurepolicydenied":
            return .featurePolicyDenied
        case "presentationmodenotapplied", "notapplied":
            // Missing transient activation is by far the most common cause when a native
            // evaluateJavaScript call tries to enter PiP without a web-content tap.
            return .requiresUserGesture
        case "promiserejected:invalidstateerror", "invalidstate", "invalidstateerror",
             "promiserejected:aborterror", "aborted", "aborterror":
            return .fullscreenOrCasting
        case "nosupport": return .pageDoesNotSupportPiP
        default: return .unknown
        }
    }
}

enum PiPRequestOutcome: Equatable {
    case success(method: String)
    case failure(reason: PiPFailureReason, detail: String?)

    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }

    var failureReason: PiPFailureReason? {
        if case let .failure(reason, _) = self { return reason }
        return nil
    }
}
