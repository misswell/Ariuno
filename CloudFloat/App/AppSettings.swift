import Foundation

/// User-facing preferences. Nothing here stores credentials, cookies or tokens.
@MainActor
final class AppSettings: ObservableObject {
    private enum Key {
        static let autoHideToolbar = "cf.settings.autoHideToolbar"
        static let toolbarAutoHideDelay = "cf.settings.toolbarAutoHideDelay"
        static let enableInPagePiPButton = "cf.settings.enableInPagePiPButton"
        static let enableBackgroundAudio = "cf.settings.enableBackgroundAudio"
        static let verboseDiagnostics = "cf.settings.verboseDiagnostics"
        static let allowLocalTestPages = "cf.settings.allowLocalTestPages"
        static let hasCompletedFirstRun = "cf.settings.hasCompletedFirstRun"
    }

    private let defaults: UserDefaults

    @Published var autoHideToolbar: Bool {
        didSet { defaults.set(autoHideToolbar, forKey: Key.autoHideToolbar) }
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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.autoHideToolbar = defaults.object(forKey: Key.autoHideToolbar) as? Bool ?? true
        let storedDelay = defaults.object(forKey: Key.toolbarAutoHideDelay) as? Double
        self.toolbarAutoHideDelay = min(max(storedDelay ?? FeatureFlags.defaultToolbarAutoHideDelay, 2), 12)
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
    }
}
