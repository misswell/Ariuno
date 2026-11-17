import XCTest
@testable import Ariuno

@MainActor
final class SessionRecoveryTests: XCTestCase {
    private var clock = Date(timeIntervalSince1970: 1_700_000_000)
    private var recovery: WebContentRecovery!

    override func setUp() {
        super.setUp()
        clock = Date(timeIntervalSince1970: 1_700_000_000)
        recovery = WebContentRecovery(
            policy: RecoveryPolicy(cooldown: 60, maxAttempts: 3, window: 600),
            now: { [weak self] in self?.clock ?? Date() }
        )
    }

    private func decision(_ trigger: RecoveryTrigger) -> RecoveryDecision {
        recovery.decide(trigger: trigger, isPiPActive: false, hasLoadedPage: true)
    }

    func testForegroundNeverReloads() {
        let result = decision(.appForegrounded)
        XCTAssertEqual(result.action, .noAction(reason: "返回前台不重载，保留现有 WebView 会话"))
        XCTAssertNil(result.userMessage)
    }

    func testNetworkRestoredNeverReloadsAutomatically() {
        let result = decision(.networkRestored)
        if case .reloadNow = result.action {
            XCTFail("network restoration must never trigger an automatic reload")
        }
        XCTAssertNotNil(result.userMessage)
    }

    func testWebContentTerminationOnlyPrompts() {
        let result = decision(.webContentTerminated)
        guard case .promptUser = result.action else {
            XCTFail("expected a user prompt, got \(result.action)")
            return
        }
        XCTAssertNotNil(result.userMessage)
    }

    func testNavigationFailureAndStallOnlyPrompt() {
        for trigger in [RecoveryTrigger.navigationFailure, .mediaStalled] {
            let result = decision(trigger)
            guard case .promptUser = result.action else {
                XCTFail("expected prompt for \(trigger), got \(result.action)")
                return
            }
        }
    }

    func testNoNonUserTriggerCanReloadNow() {
        for trigger in RecoveryTrigger.allCases where trigger != .userRequestedReload {
            let result = decision(trigger)
            if case .reloadNow = result.action {
                XCTFail("\(trigger) produced an automatic reload")
            }
        }
    }

    func testFirstUserRequestedReloadIsAllowedAndStartsCooldown() {
        let result = decision(.userRequestedReload)
        guard case .reloadNow = result.action else {
            XCTFail("expected reloadNow, got \(result.action)")
            return
        }

        recovery.noteReloadAttempt()
        XCTAssertEqual(recovery.attemptsInWindow, 1)

        let second = decision(.userRequestedReload)
        guard case .promptUser = second.action else {
            XCTFail("second reload inside cooldown must be blocked")
            return
        }
        XCTAssertEqual(recovery.attemptsInWindow, 1)
    }

    func testCooldownExpiryAllowsAnotherAttempt() {
        recovery.noteReloadAttempt()
        clock = clock.addingTimeInterval(61)
        let result = decision(.userRequestedReload)
        guard case .reloadNow = result.action else {
            XCTFail("expected reloadNow after cooldown, got \(result.action)")
            return
        }
        recovery.noteReloadAttempt()
        XCTAssertEqual(recovery.attemptsInWindow, 2)
    }

    func testAttemptLimitBlocksFurtherReloadsWithinWindow() {
        recovery.noteReloadAttempt()
        clock = clock.addingTimeInterval(61)
        recovery.noteReloadAttempt()
        clock = clock.addingTimeInterval(61)
        recovery.noteReloadAttempt()
        clock = clock.addingTimeInterval(61)

        XCTAssertEqual(recovery.attemptsInWindow, 3)
        let result = decision(.userRequestedReload)
        guard case .promptUser(let reason) = result.action else {
            XCTFail("expected attempt-limit prompt, got \(result.action)")
            return
        }
        XCTAssertTrue(reason.contains("上限"))
    }

    func testAttemptsArePrunedOutsideWindow() {
        recovery.noteReloadAttempt()
        recovery.noteReloadAttempt()
        clock = clock.addingTimeInterval(601)
        XCTAssertEqual(recovery.attemptsInWindow, 0)
        let result = decision(.userRequestedReload)
        guard case .reloadNow = result.action else {
            XCTFail("expected window pruning to allow a reload")
            return
        }
    }

    func testCooldownAlsoAppliesToPromptTriggers() {
        recovery.noteReloadAttempt()
        let result = decision(.webContentTerminated)
        if case .reloadNow = result.action {
            XCTFail("prompt trigger must not reload")
        }
        // Inside cooldown the trigger is downgraded to noAction instead of offering a prompt.
        XCTAssertEqual(result.action, .noAction(reason: "恢复冷却中"))
    }

    func testResetClearsAttemptHistory() {
        recovery.noteReloadAttempt()
        XCTAssertEqual(recovery.attemptsInWindow, 1)
        recovery.reset()
        XCTAssertEqual(recovery.attemptsInWindow, 0)
        XCTAssertNil(recovery.lastAttemptAt)
    }

    func testPolicyNeverReturnsReloadNowForNonUserTriggerEvenWhenUnlimited() {
        let policy = RecoveryPolicy(cooldown: 0, maxAttempts: 10, window: 600)
        let context = RecoveryContext(
            attemptsInWindow: 0,
            lastAttemptAt: nil,
            now: clock,
            isPiPActive: true,
            hasLoadedPage: true
        )
        for trigger in RecoveryTrigger.allCases where trigger != .userRequestedReload {
            let decision = policy.decide(trigger: trigger, context: context)
            if case .reloadNow = decision.action {
                XCTFail("policy returned reloadNow for \(trigger)")
            }
        }
        let userDecision = policy.decide(trigger: .userRequestedReload, context: context)
        guard case .reloadNow = userDecision.action else {
            XCTFail("user requested reload should be allowed when policy permits")
            return
        }
    }
}
