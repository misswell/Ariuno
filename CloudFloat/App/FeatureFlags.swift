import Foundation

/// Central feature switches and safety-relevant limits.
///
/// `nativeMediaPipelineEnabled` stays `false`: M4 requires an independently authorized,
/// documented, decodable live stream plus input/codec/session work. The app therefore does
/// not claim a native PiP media pipeline.
enum FeatureFlags {
    static let appDisplayName = "CloudFloat"
    static let gameURLString = "https://sr.mihoyo.com/cloud/"
    static let minimumIOSVersion = "17.0"

    static var isDebugBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    /// M2: inject `MediaProbe.js` into every frame.
    static let jsMediaProbeEnabled = true

    /// M4 gate. Must remain false unless a documented, authorized stream source exists.
    static let nativeMediaPipelineEnabled = false
    static let nativeMediaPipelineStatus =
        "Not Feasible：没有官方授权且文档化的独立可解码实时媒体流，无法合规实现。"

    static let diagnosticsCapacity = 800
    static let maxTrackedFrames = 24
    static let maxVideosPerFrame = 8

    /// Foreground-only, low-frequency native probe refresh. Event-driven JS messages do the
    /// real work; this is only a safety net and must be suspended in the background.
    static let foregroundProbePollInterval: TimeInterval = 3.0

    /// A `waiting`/`stalled` event must remain unresolved this long before the state machine
    /// reports `streamStalled`. It is a media-layer signal, not a server-session proof.
    static let mediaStallConfirmationDelay: TimeInterval = 8.0

    /// Minimum spacing between user-confirmed recovery reloads.
    static let recoveryAttemptCooldown: TimeInterval = 60.0
    static let maxManualRecoveryAttempts = 3
    static let recoveryAttemptWindow: TimeInterval = 600.0

    static let defaultToolbarAutoHideDelay: TimeInterval = 4.0

    /// Local test server is a developer tool only. It binds to 127.0.0.1 and is never used
    /// for the official game session.
    static var localTestServerEnabled: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    static let privacyStatement = """
    CloudFloat 不接收、不保存账号密码或登录令牌。登录完全发生在官方网页内，网站数据由 \
    WebKit 默认持久化存储管理；只有用户明确执行“清除网站数据”时才会删除。诊断日志在内存中\
    生成并在导出前脱敏，不会自动上传。服务器端云游戏会话是否持续运行无法由本 App 通过公开 \
    API 证明，界面会如实显示 UNVERIFIED。
    """
}
