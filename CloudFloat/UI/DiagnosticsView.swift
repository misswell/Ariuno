import SwiftUI
import UIKit

struct DiagnosticsView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @EnvironmentObject private var diagnostics: DiagnosticsStore
    @State private var filter: EventFilter = .all
    @State private var shareURL: URL?
    @State private var showShare = false
    @State private var showClearConfirmation = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                PiPStatusView(
                    verification: coordinator.session.verification,
                    pipStateText: coordinator.pip.state.displayText,
                    lastPlayingAt: coordinator.session.lastPlayingObservedAt,
                    lastMediaActivityAt: coordinator.session.lastMediaActivityAt,
                    sessionState: coordinator.session.state
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Section("会话") {
                detailRow("状态", coordinator.session.state.displayName)
                detailRow("网络", coordinator.session.networkStatus.displayName)
                detailRow("前台", coordinator.session.appIsForeground ? "是" : "否")
                detailRow("画中画", coordinator.session.pipVisible ? "显示中" : "未显示")
                detailRow("媒体最近播放", formatted(coordinator.session.lastPlayingObservedAt))
                detailRow("媒体最近活动", formatted(coordinator.session.lastMediaActivityAt))
                detailRow("最近进入后台", formatted(coordinator.session.lastBackgroundAt))
                detailRow("最近回到前台", formatted(coordinator.session.lastForegroundAt))
                detailRow("恢复次数", String(coordinator.session.recoveryAttempts))
                detailRow("探测轮询", coordinator.session.mediaProbePolling ? "前台低频运行" : "已暂停")
                if let failure = coordinator.session.failureReason {
                    detailRow("最近错误", failure)
                }
                if let failure = coordinator.session.lastPiPFailureReason {
                    detailRow("最近 PiP 错误", failure)
                }
            }

            Section("媒体观测（不包含 URL）") {
                detailRow("媒体类型", coordinator.media.aggregate.kind.displayName)
                detailRow("视频节点", "\(coordinator.media.aggregate.videoCount) 个")
                detailRow("播放中", "\(coordinator.media.aggregate.playingVideoCount) 个")
                detailRow("可 PiP 且播放中", "\(coordinator.media.aggregate.piPCapablePlayingVideoCount) 个")
                detailRow("Canvas", "\(coordinator.media.aggregate.canvasCount) 个")
                detailRow("iframe", "\(coordinator.media.aggregate.iframeCount) 个")
                detailRow("帧数", "\(coordinator.media.aggregate.frameCount) 个已上报 frame")
                detailRow("站点", coordinator.media.aggregate.origins.isEmpty ? "—" : coordinator.media.aggregate.origins.joined(separator: ", "))
                detailRow("最近快照", formatted(coordinator.media.lastSnapshotReceivedAt))
                if let error = coordinator.media.lastProbeError {
                    detailRow("探测错误", error)
                }
            }

            Section("环境") {
                detailRow("App", "\(environment.appVersion) (\(environment.appBuild))")
                detailRow("iOS", environment.osVersion)
                detailRow("设备", "\(environment.deviceModel)\(environment.isSimulator ? " (模拟器)" : "")")
                detailRow("语言", environment.localeIdentifier)
                detailRow("原生媒体管线 (M4)", NativePictureInPictureCoordinator.status.displayText)
            }

            Section {
                Picker("筛选", selection: $filter) {
                    ForEach(EventFilter.allCases) { item in
                        Text(item.displayName).tag(item)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("事件（\(filteredEvents.count) / \(diagnostics.events.count)）") {
                if filteredEvents.isEmpty {
                    Text("暂无符合筛选条件的事件")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filteredEvents.reversed()) { event in
                        EventRow(event: event)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("诊断")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        export(.json)
                    } label: {
                        Label("导出 JSON", systemImage: "doc.text")
                    }
                    Button {
                        export(.text)
                    } label: {
                        Label("导出纯文本", systemImage: "text.alignleft")
                    }
                    Button {
                        copyJSON()
                    } label: {
                        Label("复制 JSON 到剪贴板", systemImage: "doc.on.doc")
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("导出诊断")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    showClearConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(diagnostics.events.isEmpty)
                .accessibilityLabel("清除诊断日志")
            }
        }
        .confirmationDialog(
            "清除诊断日志？",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("清除", role: .destructive) {
                diagnostics.clear()
                coordinator.showToast("诊断日志已清除", .info)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只清除内存中的诊断事件，不影响登录状态或网站数据。")
        }
        .alert(
            "提示",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(isPresented: $showShare, onDismiss: cleanupExportFile) {
            if let shareURL {
                ShareSheet(items: [shareURL])
            }
        }
    }

    private var environment: DiagnosticsEnvironment {
        ExportDiagnostics.environment()
    }

    private var filteredEvents: [DiagnosticEvent] {
        switch filter {
        case .all:
            return diagnostics.events
        case .important:
            return diagnostics.events.filter { $0.severity >= .warning }
        case .session:
            return diagnostics.events.filter { $0.category == .session || $0.category == .recovery }
        case .media:
            return diagnostics.events.filter { $0.category == .media || $0.category == .pip }
        }
    }

    private func export(_ format: DiagnosticsExportFormat) {
        do {
            let url = try ExportDiagnostics.writeTemporaryFile(
                events: diagnostics.events,
                session: coordinator.session.diagnosticsSnapshot,
                format: format
            )
            shareURL = url
            showShare = true
        } catch {
            errorMessage = "导出失败：\(error.localizedDescription)"
        }
    }

    private func copyJSON() {
        do {
            let data = try ExportDiagnostics.jsonData(
                events: diagnostics.events,
                session: coordinator.session.diagnosticsSnapshot
            )
            guard let text = String(data: data, encoding: .utf8) else {
                errorMessage = "无法生成 JSON 文本"
                return
            }
            UIPasteboard.general.string = text
            coordinator.showToast("诊断 JSON 已复制到剪贴板", .info)
        } catch {
            errorMessage = "复制失败：\(error.localizedDescription)"
        }
    }

    private func cleanupExportFile() {
        if let shareURL {
            ExportDiagnostics.removeTemporaryExport(at: shareURL)
        }
        shareURL = nil
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.caption.weight(.medium))
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }

    private func formatted(_ date: Date?) -> String {
        guard let date else { return "—" }
        return Self.timeFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM-dd HH:mm:ss"
        return formatter
    }()
}

private enum EventFilter: String, CaseIterable, Identifiable {
    case all
    case important
    case session
    case media

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: return "全部"
        case .important: return "警告+"
        case .session: return "会话"
        case .media: return "媒体"
        }
    }
}

private struct EventRow: View {
    let event: DiagnosticEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                Text(event.category.displayName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(event.severity.displayName)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(color)
                Spacer()
                Text(Self.timeFormatter.string(from: event.timestamp))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            Text(event.code)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
            Text(event.message)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            if !event.metadata.isEmpty {
                Text(metadataText)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(8)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 3)
    }

    private var metadataText: String {
        event.metadata
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "  ")
    }

    private var color: Color {
        switch event.severity {
        case .debug: return .secondary
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}
