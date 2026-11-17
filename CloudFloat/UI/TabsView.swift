import SwiftUI
import WebKit

struct TabsView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var showCloseAllConfirmation = false
    @State private var tabCloseConfirmation: BrowserSession?

    var body: some View {
        NavigationStack {
            List {
                openedSection
                if !coordinator.tabs.recentlyClosed.snapshots.isEmpty {
                    recentSection
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("标签页")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .confirmationDialog(
                "关闭全部标签页？",
                isPresented: $showCloseAllConfirmation,
                titleVisibility: .visible
            ) {
                Button("关闭全部", role: .destructive) {
                    if coordinator.tabs.closeAllTabs(force: true) {
                        dismiss()
                    }
                }
                Button("取消", role: .cancel) {}
            }
            .alert(
                "关闭正在画中画的标签页？",
                isPresented: Binding(
                    get: { tabCloseConfirmation != nil },
                    set: { if !$0 { tabCloseConfirmation = nil } }
                )
            ) {
                Button("结束 PiP 并关闭", role: .destructive) {
                    if let session = tabCloseConfirmation {
                        coordinator.closeTab(session, force: true)
                    }
                    tabCloseConfirmation = nil
                }
                Button("取消", role: .cancel) { tabCloseConfirmation = nil }
            } message: {
                Text("该标签页正在画中画。关闭会结束浮窗播放。")
            }
        }
    }

    @ViewBuilder
    private var openedSection: some View {
        Section("打开的标签页（\(coordinator.tabs.sessions.count)）") {
            ForEach(coordinator.tabs.sessions) { session in
                tabRow(session)
            }
            .onDelete { indexSet in
                for index in indexSet {
                    close(coordinator.tabs.sessions[index])
                }
            }
        }
    }

    @ViewBuilder
    private var recentSection: some View {
        Section("最近关闭") {
            ForEach(coordinator.tabs.recentlyClosed.snapshots) { snapshot in
                Button {
                    if coordinator.tabs.restoreRecentlyClosed() != nil {
                        dismiss()
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(snapshot.title)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(2)
                        Text(snapshot.urlString)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("完成") { dismiss() }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Menu {
                Button("新建普通标签页") {
                    coordinator.createTab(isPrivate: false)
                    dismiss()
                }
                Button("新建隐私标签页") {
                    coordinator.createTab(isPrivate: true)
                    dismiss()
                }
                Divider()
                Button("关闭其他标签页") {
                    if coordinator.tabs.closeAllTabs(except: coordinator.browser) {
                        dismiss()
                    } else {
                        coordinator.showToast("有 PiP 来源标签页受保护", .warning)
                    }
                }
                Button("关闭全部标签页", role: .destructive) {
                    if coordinator.tabs.closeAllTabs() {
                        dismiss()
                    } else {
                        coordinator.showToast("有 PiP 来源标签页受保护", .warning)
                    }
                }
                Button("清空最近关闭") {
                    coordinator.tabs.clearRecentlyClosed()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            Button {
                coordinator.createTab(isPrivate: false)
                dismiss()
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("新建标签页")
        }
    }

    @ViewBuilder
    private func tabRow(_ session: BrowserSession) -> some View {
        let isActive = session.id == coordinator.tabs.activeSessionID
        Button {
            coordinator.activateTab(session)
            dismiss()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                TabPreviewImage(webView: session.webView)
                    .frame(width: 96, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(isActive ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: isActive ? 2 : 1)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(session.pageTitle.isEmpty ? "未命名页面" : session.pageTitle)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        if session.isPrivate {
                            Image(systemName: "mask")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(session.currentURL?.absoluteString ?? "空白页")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(isActive ? "当前标签页" : "后台标签页")
                        if coordinator.pipManager.isPiPActive(for: session) {
                            Label("PiP", systemImage: "pip.fill")
                        }
                        if session.isPrivate {
                            Text("隐私")
                        }
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
                Button(role: .destructive) {
                    close(session)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("关闭标签页")
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func close(_ session: BrowserSession) {
        let result = coordinator.closeTab(session)
        if result == .requiresPiPConfirmation {
            tabCloseConfirmation = session
        }
    }
}

struct TabPreviewImage: View {
    let webView: WKWebView
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color(uiColor: .secondarySystemBackground)
                    .overlay(
                        ProgressView()
                            .controlSize(.small)
                    )
            }
        }
        .task {
            image = await takeSnapshot()
        }
    }

    private func takeSnapshot() async -> UIImage? {
        await withCheckedContinuation { continuation in
            let configuration = WKSnapshotConfiguration()
            configuration.afterScreenUpdates = false
            webView.takeSnapshot(with: configuration) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}
