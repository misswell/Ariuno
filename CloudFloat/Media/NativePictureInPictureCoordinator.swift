import AVKit
import Foundation

/// M4 evaluation status. The native media pipeline remains deliberately unimplemented.
///
/// Requirements that are not met:
/// 1. There is no documented, authorized, independently accessible live media stream for the
///    official cloud game.
/// 2. An authorized input channel and a guarantee that the cloud session stays consistent are
///    both missing.
/// 3. `AVSampleBufferDisplayLayer` cannot be used as a screen-grab of an arbitrary WKWebView,
///    so it is not a lawful substitute for web PiP.
///
/// Do not enable this path by reverse-engineering login protection, DRM or private WebKit API.
enum NativeMediaPipelineStatus: Equatable {
    case notFeasible(reason: String)

    var displayText: String {
        switch self {
        case .notFeasible(let reason): return reason
        }
    }
}

enum NativeMediaPipelineError: Error, Equatable {
    case notImplemented(reason: String)
    case notAuthorized
    case noDecodableStream
}

@MainActor
protocol NativeMediaPipelineProviding: AnyObject {
    var isAvailable: Bool { get }
    func startNativePictureInPicture() async throws
}

/// Interface-only placeholder for M4. No AVSampleBufferDisplayLayer, VideoToolbox, screen
/// capture, or private API is wired up.
@MainActor
final class NativePictureInPictureCoordinator: NativeMediaPipelineProviding {
    static let status: NativeMediaPipelineStatus = .notFeasible(
        reason: "M4 Not Feasible：缺少官方授权与文档化的独立实时媒体流；不以私有 API、屏幕抓取或伪造后台权限替代。"
    )

    static let isFeatureEnabled = FeatureFlags.nativeMediaPipelineEnabled

    var isAvailable: Bool { false }

    func startNativePictureInPicture() async throws {
        throw NativeMediaPipelineError.notImplemented(reason: Self.status.displayText)
    }
}
