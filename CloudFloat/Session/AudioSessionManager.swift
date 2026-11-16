import AVFoundation
import Foundation

/// Configures AVAudioSession only while real web media is actually playing (or while PiP is
/// visible). CloudFloat never creates silent audio and never plays audio itself.
///
/// The `audio` background mode is declared because genuine video/audio playback may continue
/// while the app is in the background (including PiP). App Review 2.5.4 requires that this
/// capability be used for its stated purpose only.
@MainActor
final class AudioSessionManager {
    private var isActiveSession = false
    private var deactivationTask: Task<Void, Never>?
    private var lastReportedError: String?

    var onError: ((String) -> Void)?

    func update(
        isMediaPlaying: Bool,
        isPiPActive: Bool,
        enabled: Bool,
        appIsForeground: Bool
    ) {
        guard enabled else {
            deactivate()
            return
        }
        // Real media or a visible PiP window are the only reasons to keep the audio session.
        if isMediaPlaying || isPiPActive {
            activate()
        } else {
            scheduleDeactivation()
        }
    }

    func deactivate() {
        deactivationTask?.cancel()
        deactivationTask = nil
        guard isActiveSession else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(
                false,
                options: [.notifyOthersOnDeactivation]
            )
            isActiveSession = false
            lastReportedError = nil
        } catch {
            report(error)
        }
    }

    private func activate() {
        deactivationTask?.cancel()
        deactivationTask = nil
        guard !isActiveSession else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay])
            try session.setActive(true)
            isActiveSession = true
            lastReportedError = nil
        } catch {
            report(error)
        }
    }

    private func scheduleDeactivation() {
        guard isActiveSession, deactivationTask == nil else { return }
        deactivationTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            self?.deactivate()
            self?.deactivationTask = nil
        }
    }

    private func report(_ error: Error) {
        let description = error.localizedDescription
        guard description != lastReportedError else { return }
        lastReportedError = description
        onError?(description)
    }
}
