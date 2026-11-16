import Foundation

/// Tracks user-confirmed reload attempts and applies `RecoveryPolicy`. It intentionally has
/// no automatic reload path.
@MainActor
final class WebContentRecovery {
    private(set) var attemptDates: [Date] = []
    private(set) var lastAttemptAt: Date?
    private var policy: RecoveryPolicy
    private let now: () -> Date

    init(policy: RecoveryPolicy = RecoveryPolicy(), now: @escaping () -> Date = Date.init) {
        self.policy = policy
        self.now = now
    }

    var attemptsInWindow: Int {
        prune()
        return attemptDates.count
    }

    func decide(trigger: RecoveryTrigger, isPiPActive: Bool, hasLoadedPage: Bool) -> RecoveryDecision {
        prune()
        return policy.decide(
            trigger: trigger,
            context: RecoveryContext(
                attemptsInWindow: attemptDates.count,
                lastAttemptAt: lastAttemptAt,
                now: now(),
                isPiPActive: isPiPActive,
                hasLoadedPage: hasLoadedPage
            )
        )
    }

    func noteReloadAttempt() {
        let date = now()
        attemptDates.append(date)
        trimToWindow()
        lastAttemptAt = date
    }

    func reset() {
        attemptDates.removeAll()
        lastAttemptAt = nil
    }

    private func prune() {
        let cutoff = now().addingTimeInterval(-policy.window)
        attemptDates.removeAll { $0 < cutoff }
        if let last = lastAttemptAt, last < cutoff {
            lastAttemptAt = nil
        }
    }

    private func trimToWindow() {
        let cutoff = now().addingTimeInterval(-policy.window)
        attemptDates.removeAll { $0 < cutoff }
    }
}
