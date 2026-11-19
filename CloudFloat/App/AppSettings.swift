import Foundation

/// User-facing preferences. Nothing here stores credentials, cookies or tokens.
@MainActor
final class AppSettings: ObservableObject {
    private enum Key {
        static let autoHideToolbar = "cf.settings.autoHideToolbar"
        static let autoHideToolbarExplicit = "cf.settings.autoHideToolbar.explicit"
        static let toolbarAutoHideDelay = "cf.settings.toolbarAutoHideDelay"
        static let collapseToolbarToBallOnOpen = "cf.settings.collapseToolbarToBallOnOpen"
        static let floatingBallX = "cf.settings.floatingBallX"
        static let floatingBallY = "cf.settings.floatingBallY"
        static let floatingBallDiameter = "cf.settings.floatingBallDiameter"
        static let floatingBallEdge = "cf.settings.floatingBallEdge"
        static let fullscreenInsetTop = "cf.settings.fullscreenInsetTop"
        static let fullscreenInsetBottom = "cf.settings.fullscreenInsetBottom"
        static let fullscreenInsetLeft = "cf.settings.fullscreenInsetLeft"
        static let fullscreenInsetRight = "cf.settings.fullscreenInsetRight"
        static let enableInPagePiPButton = "cf.settings.enableInPagePiPButton"
        static let enableBackgroundAudio = "cf.settings.enableBackgroundAudio"
        static let verboseDiagnostics = "cf.settings.verboseDiagnostics"
        static let allowLocalTestPages = "cf.settings.allowLocalTestPages"
        static let hasCompletedFirstRun = "cf.settings.hasCompletedFirstRun"
        static let searchEngine = "cf.settings.searchEngine"
        static let requestDesktopSite = "cf.settings.requestDesktopSite"
        static let desktopViewportWidth = "cf.settings.desktopViewportWidth"
    }

    private let defaults: UserDefaults

    @Published var autoHideToolbar: Bool {
        didSet {
            defaults.set(autoHideToolbar, forKey: Key.autoHideToolbar)
            defaults.set(true, forKey: Key.autoHideToolbarExplicit)
        }
    }

    @Published var toolbarAutoHideDelay: TimeInterval {
        didSet {
            let clamped = min(max(toolbarAutoHideDelay, 2), 12)
            if clamped != toolbarAutoHideDelay {
                toolbarAutoHideDelay = clamped
                return
            }
            defaults.set(clamped, forKey: Key.toolbarAutoHideDelay)
        }
    }

    /// Collapse the browser chrome into a draggable floating ball when entering a page.
    /// Off by default; the chrome always exposes a one-tap "全屏" button.
    @Published var collapseToolbarToBallOnOpen: Bool {
        didSet { defaults.set(collapseToolbarToBallOnOpen, forKey: Key.collapseToolbarToBallOnOpen) }
    }

    /// Normalized (0...1) floating-ball position, persisted across launches.
    @Published var floatingBallX: Double {
        didSet { defaults.set(floatingBallX, forKey: Key.floatingBallX) }
    }

    @Published var floatingBallY: Double {
        didSet { defaults.set(floatingBallY, forKey: Key.floatingBallY) }
    }

    /// Last edge the floating ball snapped to. Persisting it keeps the ball on the same side
    /// across launches and orientation changes instead of re-picking by nearest distance.
    @Published var floatingBallEdge: String {
        didSet { defaults.set(floatingBallEdge, forKey: Key.floatingBallEdge) }
    }

    /// Floating-ball diameter in points (40...80). Persisted so the chosen size survives launches.
    @Published var floatingBallDiameter: Double {
        didSet {
            let clamped = min(max(floatingBallDiameter, 40), 80)
            if clamped != floatingBallDiameter {
                floatingBallDiameter = clamped
                return
            }
            defaults.set(clamped, forKey: Key.floatingBallDiameter)
        }
    }

    /// Extra margins around the web content in fullscreen. Rounded corners and the notch can
    /// cover page controls; these insets let the user keep a tappable border.
    @Published var fullscreenInsetTop: Double {
        didSet {
            let clamped = Self.clampInset(fullscreenInsetTop)
            if clamped != fullscreenInsetTop {
                fullscreenInsetTop = clamped
                return
            }
            defaults.set(clamped, forKey: Key.fullscreenInsetTop)
        }
    }

    @Published var fullscreenInsetBottom: Double {
        didSet {
            let clamped = Self.clampInset(fullscreenInsetBottom)
            if clamped != fullscreenInsetBottom {
                fullscreenInsetBottom = clamped
                return
            }
            defaults.set(clamped, forKey: Key.fullscreenInsetBottom)
        }
    }

    @Published var fullscreenInsetLeft: Double {
        didSet {
            let clamped = Self.clampInset(fullscreenInsetLeft)
            if clamped != fullscreenInsetLeft {
                fullscreenInsetLeft = clamped
                return
            }
            defaults.set(clamped, forKey: Key.fullscreenInsetLeft)
        }
    }

    @Published var fullscreenInsetRight: Double {
        didSet {
            let clamped = Self.clampInset(fullscreenInsetRight)
            if clamped != fullscreenInsetRight {
                fullscreenInsetRight = clamped
                return
            }
            defaults.set(clamped, forKey: Key.fullscreenInsetRight)
        }
    }

    private static func clampInset(_ value: Double) -> Double {
        min(max(value, 0), 80)
    }

    /// Adds a small in-page picture-in-picture control. A real tap inside the web content is
    /// the only reliable way to satisfy WebKit's user-activation requirement.
    @Published var enableInPagePiPButton: Bool {
        didSet { defaults.set(enableInPagePiPButton, forKey: Key.enableInPagePiPButton) }
    }

    /// Configures AVAudioSession for genuine media playback only. CloudFloat never plays
    /// silent audio to keep itself alive.
    @Published var enableBackgroundAudio: Bool {
        didSet { defaults.set(enableBackgroundAudio, forKey: Key.enableBackgroundAudio) }
    }

    @Published var verboseDiagnostics: Bool {
        didSet { defaults.set(verboseDiagnostics, forKey: Key.verboseDiagnostics) }
    }

    /// Debug/QA-only local test pages. Disabled by default in Release builds.
    @Published var allowLocalTestPages: Bool {
        didSet { defaults.set(allowLocalTestPages, forKey: Key.allowLocalTestPages) }
    }

    @Published private(set) var hasCompletedFirstRun: Bool {
        didSet { defaults.set(hasCompletedFirstRun, forKey: Key.hasCompletedFirstRun) }
    }

    @Published var searchEngine: SearchEngine {
        didSet { defaults.set(searchEngine.rawValue, forKey: Key.searchEngine) }
    }

    /// Request desktop HTML and use a desktop UA for the current pages. Off by default.
    @Published var requestDesktopSite: Bool {
        didSet { defaults.set(requestDesktopSite, forKey: Key.requestDesktopSite) }
    }

    /// CSS viewport width used when desktop mode is on. WebKit scales it to the screen.
    @Published var desktopViewportWidth: Double {
        didSet {
            let clamped = min(max(desktopViewportWidth, 800), 1920)
            if clamped != desktopViewportWidth {
                desktopViewportWidth = clamped
                return
            }
            defaults.set(clamped, forKey: Key.desktopViewportWidth)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if ProcessInfo.processInfo.arguments.contains("-CFResetFloatingBall") {
            for key in [
                Key.floatingBallX, Key.floatingBallY, Key.floatingBallEdge
            ] {
                defaults.removeObject(forKey: key)
            }
        }
        // Keep the browser toolbar visible by default. Auto-hide was previously on and made
        // bookmark/share/tab buttons hard to find; only honour it when the user chose it.
        let explicitlySet = defaults.bool(forKey: Key.autoHideToolbarExplicit)
        self.autoHideToolbar = explicitlySet
            ? (defaults.object(forKey: Key.autoHideToolbar) as? Bool ?? false)
            : false
        let storedDelay = defaults.object(forKey: Key.toolbarAutoHideDelay) as? Double
        self.toolbarAutoHideDelay = min(max(storedDelay ?? FeatureFlags.defaultToolbarAutoHideDelay, 2), 12)
        self.collapseToolbarToBallOnOpen =
            defaults.object(forKey: Key.collapseToolbarToBallOnOpen) as? Bool ?? false
        self.floatingBallX =
            min(max(defaults.object(forKey: Key.floatingBallX) as? Double ?? 0.90, 0.05), 0.95)
        self.floatingBallY =
            min(max(defaults.object(forKey: Key.floatingBallY) as? Double ?? 0.62, 0.08), 0.92)
        self.floatingBallDiameter =
            min(max(defaults.object(forKey: Key.floatingBallDiameter) as? Double ?? 56, 40), 80)
        self.floatingBallEdge = defaults.string(forKey: Key.floatingBallEdge) ?? "right"
        self.fullscreenInsetTop = Self.clampInset(defaults.object(forKey: Key.fullscreenInsetTop) as? Double ?? 0)
        self.fullscreenInsetBottom = Self.clampInset(defaults.object(forKey: Key.fullscreenInsetBottom) as? Double ?? 0)
        self.fullscreenInsetLeft = Self.clampInset(defaults.object(forKey: Key.fullscreenInsetLeft) as? Double ?? 0)
        self.fullscreenInsetRight = Self.clampInset(defaults.object(forKey: Key.fullscreenInsetRight) as? Double ?? 0)
        self.enableInPagePiPButton =
            defaults.object(forKey: Key.enableInPagePiPButton) as? Bool ?? true
        self.enableBackgroundAudio =
            defaults.object(forKey: Key.enableBackgroundAudio) as? Bool ?? true
        self.verboseDiagnostics =
            defaults.object(forKey: Key.verboseDiagnostics) as? Bool ?? FeatureFlags.isDebugBuild
        self.allowLocalTestPages =
            defaults.object(forKey: Key.allowLocalTestPages) as? Bool
            ?? FeatureFlags.localTestServerEnabled
        self.hasCompletedFirstRun =
            defaults.object(forKey: Key.hasCompletedFirstRun) as? Bool ?? false
        self.searchEngine = SearchEngine(
            rawValue: defaults.string(forKey: Key.searchEngine) ?? ""
        ) ?? .duckduckgo
        self.requestDesktopSite =
            defaults.object(forKey: Key.requestDesktopSite) as? Bool ?? false
        self.desktopViewportWidth = min(
            max(defaults.object(forKey: Key.desktopViewportWidth) as? Double ?? 1280, 800),
            1920
        )
    }

    func markFirstRunCompleted() {
        hasCompletedFirstRun = true
    }

    func resetToDefaults() {
        autoHideToolbar = true
        toolbarAutoHideDelay = FeatureFlags.defaultToolbarAutoHideDelay
        enableInPagePiPButton = true
        enableBackgroundAudio = true
        verboseDiagnostics = FeatureFlags.isDebugBuild
        allowLocalTestPages = FeatureFlags.localTestServerEnabled
        requestDesktopSite = false
        desktopViewportWidth = 1280
    }
}
