import Foundation

enum RecoveryTrigger: String, CaseIterable, Equatable {
    case appForegrounded
    case networkRestored
    case webContentTerminated
    case navigationFailure
    case mediaStalled
    case userRequestedReload

    var displayName: String {
        switch self {
        case .appForegrounded: return "返回前台"
        case .networkRestored: return "网络恢复"
        case .webContentTerminated: return "WebContent 崩溃"
        case .navigationFailure: return "导航失败"
        case .mediaStalled: return "媒体停滞"
        case .userRequestedReload: return "用户请求重新加载"
        }
    }
}

enum RecoveryAction: Equatable {
    case noAction(reason: String)
    case promptUser(reason: String)
    case reloadNow(reason: String)
}

struct RecoveryDecision: Equatable {
    let trigger: RecoveryTrigger
    let action: RecoveryAction
    let userMessage: String?
}

struct RecoveryContext: Equatable {
    let attemptsInWindow: Int
    let lastAttemptAt: Date?
    let now: Date
    let isPiPActive: Bool
    let hasLoadedPage: Bool
}

/// Deliberately conservative: there is no automatic reload path. Reloading can restart the
/// cloud game and consume billed session time, so a reload always requires an explicit user
/// confirmation. The policy only tells the UI whether a confirmation may be offered.
struct RecoveryPolicy {
    var cooldown: TimeInterval = FeatureFlags.recoveryAttemptCooldown
    var maxAttempts: Int = FeatureFlags.maxManualRecoveryAttempts
    var window: TimeInterval = FeatureFlags.recoveryAttemptWindow

    func decide(trigger: RecoveryTrigger, context: RecoveryContext) -> RecoveryDecision {
        switch trigger {
        case .appForegrounded:
            return RecoveryDecision(
                trigger: trigger,
                action: .noAction(reason: "返回前台不重载，保留现有 WebView 会话"),
                userMessage: nil
            )

        case .networkRestored:
            return RecoveryDecision(
                trigger: trigger,
                action: .noAction(reason: "网络恢复后先等待现有页面自行恢复"),
                userMessage: "网络已恢复；如画面没有恢复，可在确认后手动重新连接。"
            )

        case .webContentTerminated:
            return limitDecision(
                trigger: trigger,
                context: context,
                allowedMessage: "网页进程已终止，必须由你确认后才能重新加载页面。"
            )

        case .navigationFailure:
            return limitDecision(
                trigger: trigger,
                context: context,
                allowedMessage: "页面加载失败；请确认证书、网络和登录状态后再重试。"
            )

        case .mediaStalled:
            return limitDecision(
                trigger: trigger,
                context: context,
                allowedMessage: "视频已长时间没有进展；建议先返回游戏确认，再决定是否重连。"
            )

        case .userRequestedReload:
            if context.attemptsInWindow >= maxAttempts {
                return RecoveryDecision(
                    trigger: trigger,
                    action: .promptUser(
                        reason: "\(Int(window / 60)) 分钟内已尝试 \(context.attemptsInWindow) 次，达到上限"
                    ),
                    userMessage: "短时间内重新加载次数过多。为避免重复启动云游戏会话，请稍后再试或退出会话。"
                )
            }
            if let last = context.lastAttemptAt, context.now.timeIntervalSince(last) < cooldown {
                let remaining = Int(ceil(cooldown - context.now.timeIntervalSince(last)))
                return RecoveryDecision(
                    trigger: trigger,
                    action: .promptUser(reason: "恢复冷却中，剩余 \(remaining) 秒"),
                    userMessage: "距上次重载不足 \(Int(cooldown)) 秒。请等待 \(remaining) 秒，避免重复计费。"
                )
            }
            let pipNote = context.isPiPActive ? "重新加载会先结束当前画中画浮窗。" : ""
            return RecoveryDecision(
                trigger: trigger,
                action: .reloadNow(reason: "用户已确认重新加载"),
                userMessage: pipNote
            )
        }
    }

    private func limitDecision(
        trigger: RecoveryTrigger,
        context: RecoveryContext,
        allowedMessage: String
    ) -> RecoveryDecision {
        if context.attemptsInWindow >= maxAttempts {
            return RecoveryDecision(
                trigger: trigger,
                action: .noAction(reason: "恢复次数达到上限"),
                userMessage: "短时间内恢复次数已达到上限，请退出会话或稍后再试，以避免重复启动云游戏。"
            )
        }
        if let last = context.lastAttemptAt, context.now.timeIntervalSince(last) < cooldown {
            return RecoveryDecision(
                trigger: trigger,
                action: .noAction(reason: "恢复冷却中"),
                userMessage: "恢复操作冷却中，请稍后再试。"
            )
        }
        return RecoveryDecision(
            trigger: trigger,
            action: .promptUser(reason: trigger.displayName),
            userMessage: allowedMessage
        )
    }
}
