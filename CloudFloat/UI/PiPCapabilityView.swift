import SwiftUI

struct PiPCapabilityView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var report: PiPCapabilityReport?
    @State private var isChecking = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let report {
                        verdictCard(report)
                        PiPStatusView(
                            verification: coordinator.session.verification,
                            pipStateText: coordinator.pip.state.displayText,
                            lastPlayingAt: coordinator.session.lastPlayingObservedAt,
                            lastMediaActivityAt: coordinator.session.lastMediaActivityAt,
                            sessionState: coordinator.session.state
                        )
                        checklistCard(report)
                        mediaCard(report)
                        if !coordinator.media.frames.isEmpty {
                            framesCard
                        }
                        notesCard(report)
                        actions(report)
                    } else {
                        ProgressView("正在读取媒体状态…")
                            .padding(.top, 60)
                    }
                }
                .padding(16)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("画中画能力检测")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { @MainActor in
                            await refresh()
                        }
                    } label: {
                        if isChecking {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("重新检测", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(isChecking)
                }
            }
            .task {
                await refresh()
            }
        }
    }

    // MARK: - Cards

    private func verdictCard(_ report: PiPCapabilityReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(verdictColor(report).opacity(0.14))
                        .frame(width: 48, height: 48)
                    Image(systemName: report.availability.isAvailable ? "pip.fill" : "pip")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(verdictColor(report))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(report.verdictTitle)
                        .font(.headline)
                    Text(report.verdictDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 6) {
                Text(report.availability.isAvailable ? "HTML5 PiP 可用" : "当前不可用")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(verdictColor(report))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(verdictColor(report).opacity(0.12), in: Capsule())
                if report.isSimulator {
                    Text("模拟器")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.12), in: Capsule())
                }
                Spacer()
                Text(Self.timeFormatter.string(from: report.generatedAt))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    private func checklistCard(_ report: PiPCapabilityReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            cardTitle("能力检查", systemImage: "checklist")
            checkRow("系统支持 PiP", detail: "isPictureInPictureSupported()", pass: report.platformSupportsPiP)
            checkRow("WebView 允许 PiP", detail: "allowsPictureInPictureMediaPlayback = true", pass: report.webViewAllowsPiP)
            checkRow("探测脚本已加载", detail: "MediaProbe.js", pass: report.probeScriptLoaded)
            checkRow("已收到媒体快照", detail: report.hasProbeSnapshot ? "是" : "尚未收到；请先播放游戏画面", pass: report.hasProbeSnapshot)
            checkRow("存在 HTML 视频", detail: "\(report.aggregate.videoCount) 个 video 节点", pass: report.aggregate.hasAnyVideo)
            checkRow("视频正在播放", detail: "\(report.aggregate.playingVideoCount) 个播放中", pass: report.aggregate.hasPlayingVideo)
            checkRow("视频支持 HTML5 PiP", detail: "\(report.aggregate.piPCapablePlayingVideoCount) 个可 PiP 且播放中", pass: report.aggregate.hasPiPCapablePlayingVideo)
            if let video = report.aggregate.bestVideo, video.pipFeatureAllowed == false {
                checkRow("Permissions Policy 允许", detail: "iframe 禁止 picture-in-picture", pass: false)
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    private func mediaCard(_ report: PiPCapabilityReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            cardTitle("页面媒体结构", systemImage: "rectangle.stack.badge.play")
            detailRow("媒体类型", report.aggregate.kind.displayName)
            detailRow("视频节点", "\(report.aggregate.videoCount) 个 / 播放中 \(report.aggregate.playingVideoCount) 个")
            detailRow("Canvas", "\(report.aggregate.canvasCount) 个")
            detailRow("iframe", "\(report.aggregate.iframeCount) 个")
            detailRow("已上报 frame", "\(report.aggregate.frameCount) 个")
            detailRow("站点来源", report.aggregate.origins.isEmpty ? "—" : report.aggregate.origins.joined(separator: ", "))
            detailRow("页面主机", report.pageHost ?? "尚未加载页面")
            detailRow("会话状态", report.sessionState.displayName)
            detailRow("最近快照", coordinator.media.lastSnapshotReceivedAt.map { Self.timeFormatter.string(from: $0) } ?? "—")
            if let video = report.aggregate.bestVideo {
                Divider()
                Text("最佳候选视频")
                    .font(.caption.weight(.semibold))
                detailRow("分辨率", video.resolutionDescription)
                detailRow("状态", video.playbackStateDescription)
                detailRow("readyState", String(video.readyState))
                detailRow("PiP 支持", video.pipSupported ? "是" : "否")
                detailRow("演示模式", video.presentationMode ?? "inline")
                detailRow("DRM", video.drmProtected ? "是（可能禁止 PiP）" : "否")
                detailRow("媒体来源类型", video.srcKind)
                if let allowed = video.pipFeatureAllowed {
                    detailRow("Permissions Policy", allowed ? "允许" : "禁止")
                }
            }
            if report.aggregate.kind == .canvas {
                warningNote("只检测到 Canvas/WebGL。屏幕上虽然有画面，但没有可交给 HTML5 PiP 的 video 元素，因此无法用系统网页 PiP 实现浮窗。")
            }
            if report.aggregate.kind == .crossOriginFrame {
                warningNote("当前可访问 frame 中没有视频。媒体可能在跨域 iframe 内；每个 frame 会独立运行探测并上报，请等待子 frame 数据或查看诊断。")
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    private var framesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardTitle("Frame 明细（脱敏）", systemImage: "square.on.square")
            ForEach(sortedFrames) { frame in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(frame.origin)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .lineLimit(1)
                        Spacer()
                        Text(frame.isTopFrame ? "主 frame" : "子 frame")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text("video \(frame.videoCount) · canvas \(frame.canvasCount) · iframe \(frame.iframeCount) · \(frame.visibilityState)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    ForEach(frame.videos) { video in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(video.playing ? Color.green : Color.secondary)
                                .frame(width: 5, height: 5)
                            Text("#\(video.index) \(video.playbackStateDescription) · \(video.resolutionDescription) · \(video.pipSupported ? "PiP✓" : "PiP✗")")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    if frame.videos.isEmpty {
                        Text("无可访问 video 节点")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(10)
                .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    private func notesCard(_ report: PiPCapabilityReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            cardTitle("结论与限制", systemImage: "exclamationmark.bubble")
            ForEach(Array(report.notes.enumerated()), id: \.offset) { _, note in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(Color.orange.opacity(0.8))
                        .frame(width: 5, height: 5)
                        .padding(.top, 6)
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Divider()
            Text("本检测只描述当前网页的媒体观测，不证明服务器端云游戏会话、自动战斗或游戏进度仍在继续。")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(cardBackground)
    }

    private func actions(_ report: PiPCapabilityReport) -> some View {
        VStack(spacing: 10) {
            Button {
                coordinator.continueGame()
                dismiss()
            } label: {
                Label(
                    coordinator.browser.isShowingBlankPage ? "打开官方云游戏页面" : "进入游戏页面",
                    systemImage: "play.rectangle.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button {
                Task { @MainActor in
                    await refresh()
                }
            } label: {
                Label("重新检测", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(isChecking)
        }
    }

    // MARK: - Helpers

    private var sortedFrames: [MediaFrameSnapshot] {
        coordinator.media.frames.values.sorted { lhs, rhs in
            if lhs.isTopFrame != rhs.isTopFrame {
                return lhs.isTopFrame
            }
            return lhs.receivedAt > rhs.receivedAt
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color(uiColor: .secondarySystemGroupedBackground))
    }

    private func cardTitle(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tint)
            Text(title)
                .font(.subheadline.weight(.semibold))
        }
    }

    private func checkRow(_ title: String, detail: String, pass: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: pass ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(pass ? .green : .orange)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.medium))
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
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

    private func warningNote(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.orange)
                .padding(.top, 2)
            Text(text)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func verdictColor(_ report: PiPCapabilityReport) -> Color {
        if report.availability.isAvailable { return .green }
        if !report.platformSupportsPiP { return .orange }
        return .orange
    }

    @MainActor
    private func refresh() async {
        isChecking = true
        coordinator.media.refreshNow()
        try? await Task.sleep(nanoseconds: 900_000_000)
        report = coordinator.makePiPCapabilityReport(refresh: false)
        isChecking = false
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
