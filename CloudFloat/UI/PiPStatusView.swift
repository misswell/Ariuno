import SwiftUI

struct PiPStatusView: View {
    let verification: PlaybackVerification
    let pipStateText: String
    let lastPlayingAt: Date?
    let lastMediaActivityAt: Date?
    let sessionState: GameSessionState
    var showsHeader: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showsHeader {
                HStack(spacing: 8) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .foregroundStyle(.tint)
                    Text("三层状态")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(sessionState.displayName)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }
            }

            StatusRow(
                title: "画中画浮窗",
                value: verification.pipVisible ? "已显示" : "未显示",
                detail: "\(pipStateText)。关闭浮窗不等于游戏结束，但服务器会话仍需返回游戏人工确认（UNVERIFIED）。",
                tone: verification.pipVisible ? .positive : .neutral
            )

            StatusRow(
                title: "媒体实时性",
                value: verification.mediaFlowingObserved ? "最近观测到播放" : "未观测到播放",
                detail: mediaDetail,
                tone: verification.mediaFlowingObserved ? .positive : .warning
            )

            StatusRow(
                title: "服务器会话",
                value: "UNVERIFIED",
                detail: "Ariuno 无法通过公开 API 证明云端游戏会话、游戏进度或自动战斗仍在运行。只有人工返回游戏确认进度变化，才能作为挂机证据。",
                tone: .warning
            )

            Divider()

            Text(verification.overallText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(verification.isFullBackgroundIdleVerified ? .green : .secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground).opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }

    private var mediaDetail: String {
        var parts: [String] = []
        if let lastPlayingAt {
            parts.append("最近观测到播放：\(Self.timeFormatter.string(from: lastPlayingAt))")
        }
        if let lastMediaActivityAt, lastMediaActivityAt != lastPlayingAt {
            parts.append("最近媒体活动：\(Self.timeFormatter.string(from: lastMediaActivityAt))")
        }
        parts.append("后台 JS 定时器可能被系统暂停，因此这只是“最近观测”，不是持续存活证明。")
        return parts.joined(separator: "。")
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

private struct StatusRow: View {
    enum Tone {
        case positive
        case warning
        case neutral

        var color: Color {
            switch self {
            case .positive: return .green
            case .warning: return .orange
            case .neutral: return .secondary
            }
        }
    }

    let title: String
    let value: String
    let detail: String
    let tone: Tone

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(tone.color)
                .frame(width: 8, height: 8)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.footnote.weight(.semibold))
                    Spacer()
                    Text(value)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tone.color)
                }
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct PiPStatusSheet: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    PiPStatusView(
                        verification: coordinator.session.verification,
                        pipStateText: coordinator.pip.state.displayText,
                        lastPlayingAt: coordinator.session.lastPlayingObservedAt,
                        lastMediaActivityAt: coordinator.session.lastMediaActivityAt,
                        sessionState: coordinator.session.state
                    )
                    detailCard
                    Text("本页面只展示观测值，不提供“已挂机”结论。真机验证步骤与记录模板见 docs/qa-matrix.md。")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("会话状态")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private var detailCard: some View {
        VStack(spacing: 10) {
            detailRow("状态", coordinator.session.state.displayName)
            detailRow("网络", coordinator.session.networkStatus.displayName)
            detailRow("前台", coordinator.session.appIsForeground ? "是" : "否")
            detailRow("恢复次数", String(coordinator.session.recoveryAttempts))
            detailRow("媒体类型", coordinator.media.aggregate.kind.displayName)
            detailRow("视频节点", "\(coordinator.media.aggregate.videoCount) 个 / 播放中 \(coordinator.media.aggregate.playingVideoCount)")
            if let failure = coordinator.session.failureReason {
                detailRow("最近错误", failure)
            }
            if let date = coordinator.session.lastBackgroundAt {
                detailRow("上次后台", Self.dateFormatter.string(from: date))
            }
            if let date = coordinator.session.lastForegroundAt {
                detailRow("上次前台", Self.dateFormatter.string(from: date))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground).opacity(0.72))
        )
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(value)
                .font(.caption.weight(.medium))
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
