import SwiftUI

/// Ariuno start page: address entry, quick actions (new tab, bookmarks, history,
/// downloads), recently visited sites and recently closed tabs. Nothing here is a
/// hardcoded cloud-game entry; every destination comes from user data.
struct BrowserStartPageView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @EnvironmentObject private var settings: AppSettings
    @State private var addressText = ""
    @State private var showCapability = false
    @State private var showHistory = false
    @State private var showBookmarks = false
    @State private var showDownloads = false
    @FocusState private var addressFieldFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    addressCard
                    quickActions
                    recentlyVisitedSection
                    recentlyClosedSection
                    bookmarkSection
                    VStack(spacing: 12) {
                        capabilityCard
                        NavigationLink {
                            DiagnosticsView()
                        } label: {
                            HomeActionCard(
                                title: "诊断",
                                subtitle: "会话状态、媒体事件与隐私化日志",
                                systemImage: "waveform.path.ecg",
                                tint: .teal,
                                badge: coordinator.session.state.displayName
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            SettingsView()
                        } label: {
                            HomeActionCard(
                                title: "设置",
                                subtitle: "工具栏、PiP 控件、音频与网站数据",
                                systemImage: "gearshape",
                                tint: .indigo,
                                badge: nil
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    footer
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .background(background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $showHistory) {
            HistoryView()
                .environmentObject(coordinator)
        }
        .sheet(isPresented: $showBookmarks) {
            BookmarksView(canAddCurrentPage: false)
                .environmentObject(coordinator)
        }
        .sheet(isPresented: $showDownloads) {
            DownloadsView()
                .environmentObject(coordinator)
        }
        .sheet(isPresented: $showCapability) {
            PiPCapabilityView()
                .environmentObject(coordinator)
                .environmentObject(coordinator.settings)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "rectangle.on.rectangle.angled")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ariuno")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("现代浏览器 · 内置画中画")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            if !isScreenshotMode {
                HStack(spacing: 6) {
                    Circle()
                        .fill(coordinator.pip.platformSupportsPiP ? Color.green : Color.orange)
                        .frame(width: 7, height: 7)
                    Text(coordinator.pip.platformSupportsPiP ? "系统支持画中画" : "当前环境不支持系统画中画")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if coordinator.hasStartedBrowser {
                    Text(coordinator.session.state.displayName)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    private var isScreenshotMode: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-CFScreenshotMode")
        #else
        return false
        #endif
    }

    // MARK: - Address

    private var addressCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "globe")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.tint)
                TextField("搜索或输入网址", text: $addressText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .submitLabel(.go)
                    .focused($addressFieldFocused)
                    .font(.system(size: 15, weight: .medium))
                    .onSubmit(openAddress)
                Button {
                    openAddress()
                } label: {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .disabled(addressText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(12)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            Button {
                coordinator.continueBrowsing()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 16, weight: .bold))
                    Text(coordinator.hasStartedBrowser ? "继续浏览" : "开始浏览")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    if coordinator.session.pipVisible {
                        Label("PiP", systemImage: "pip.fill")
                            .font(.caption2.weight(.semibold))
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground).opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }

    // MARK: - Quick actions

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                QuickActionButton(title: "新建", systemImage: "plus.square.on.square") {
                    addressFieldFocused = false
                    coordinator.createTab()
                }
                QuickActionButton(title: "书签", systemImage: "bookmark") {
                    showBookmarks = true
                }
                QuickActionButton(title: "历史", systemImage: "clock") {
                    showHistory = true
                }
                QuickActionButton(title: "下载", systemImage: "arrow.down.circle") {
                    showDownloads = true
                }
            }

            Text("常用网站")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 2)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 92), spacing: 10)],
                spacing: 10
            ) {
                ForEach(StartPageShortcut.defaults) { shortcut in
                    Button {
                        addressFieldFocused = false
                        coordinator.openURL(shortcut.url)
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: shortcut.systemImage)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.tint)
                            Text(shortcut.title)
                                .font(.caption2.weight(.medium))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(uiColor: .secondarySystemBackground).opacity(0.72))
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                }
            }
        }
    }

    // MARK: - Recently visited

    private var recentlyVisitedSection: some View {
        SectionCard(header: "最近访问", headerTrailing: "历史记录") {
            showHistory = true
        } content: {
            let entries = coordinator.library.history.entries.prefix(5)
            if entries.isEmpty {
                Text("暂无访问记录；隐私标签页不会记录历史")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(entries)) { entry in
                        Button {
                            if let url = entry.url {
                                coordinator.openURL(url)
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "globe")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.tint)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.title.isEmpty ? entry.urlString : entry.title)
                                        .font(.subheadline.weight(.medium))
                                        .lineLimit(1)
                                    Text(entryDisplayHost(entry))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Text(entryRelativeTime(entry.visitedAt))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Recently closed tabs

    private var recentlyClosedSection: some View {
        SectionCard(header: "最近关闭的标签页") {
            // informational header
        } content: {
            let snapshots = coordinator.tabs.recentlyClosed.snapshots.prefix(3)
            if snapshots.isEmpty {
                Text("暂无最近关闭的标签页")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(snapshots)) { snapshot in
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.uturn.backward.circle")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(snapshot.title.isEmpty ? snapshot.urlString : snapshot.title)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                Text(snapshot.urlString)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                    }
                    Button {
                        coordinator.restoreRecentlyClosedTab()
                    } label: {
                        Label("恢复关闭的标签页", systemImage: "arrow.uturn.backward")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Bookmarks

    private var bookmarkSection: some View {
        SectionCard(header: "书签", headerTrailing: "全部书签") {
            showBookmarks = true
        } content: {
            let bookmarks = coordinator.bookmarks.bookmarks.prefix(5)
            if bookmarks.isEmpty {
                Text("在浏览网页时可通过分享菜单或书签页添加收藏")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(bookmarks)) { bookmark in
                        Button {
                            if let url = bookmark.url {
                                coordinator.openURL(url)
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "bookmark.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.tint)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(bookmark.title)
                                        .font(.subheadline.weight(.medium))
                                        .lineLimit(1)
                                    Text(bookmark.urlString)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Capability

    private var capabilityCard: some View {
        Button {
            showCapability = true
        } label: {
            HomeActionCard(
                title: "画中画能力检测",
                subtitle: capabilitySubtitle,
                systemImage: "pip",
                tint: .blue,
                badge: capabilityBadge
            )
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("非官方浏览器")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("任何网页都可浏览；画中画是可选能力，需由网页视频自身支持。Ariuno 不保存账号密码或令牌，也不宣称已经验证后台挂机成功。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 6)
    }

    private var capabilityBadge: String? {
        if isScreenshotMode { return nil }
        if !coordinator.pip.platformSupportsPiP {
            return "不支持"
        }
        if coordinator.media.lastSnapshotReceivedAt == nil {
            return "待检测"
        }
        return coordinator.pip.availability.isAvailable ? "可用" : "不可用"
    }

    private var capabilitySubtitle: String {
        if isScreenshotMode { return "平台、WebView 与网页视频三层能力检查" }
        if !coordinator.pip.platformSupportsPiP {
            return "此设备/模拟器不支持 PiP，检测仍会展示媒体结构"
        }
        return "平台、WebView 与网页视频三层能力检查"
    }

    private var background: some View {
        LinearGradient(
            colors: [
                Color(uiColor: .systemBackground),
                Color(uiColor: .secondarySystemBackground).opacity(0.7),
                Color.accentColor.opacity(0.06)
            ],
            startPoint: .top,
            endPoint: .bottomTrailing
        )
    }

    private func openAddress() {
        addressFieldFocused = false
        coordinator.openAddressText(addressText)
    }

    private func entryDisplayHost(_ entry: HistoryEntry) -> String {
        entry.url?.host ?? entry.urlString
    }

    private func entryRelativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Building blocks

/// Built-in start-page shortcuts. This list is compiled into the app (it is not user-editable);
/// user-managed destinations live in Bookmarks and History.
struct StartPageShortcut: Identifiable, Equatable {
    let id: String
    let title: String
    let systemImage: String
    let urlString: String

    var url: URL { URL(string: urlString)! }

    static let defaults: [StartPageShortcut] = [
        StartPageShortcut(id: "bing", title: "Bing", systemImage: "b.circle", urlString: "https://www.bing.com"),
        StartPageShortcut(id: "github", title: "GitHub", systemImage: "chevron.left.forwardslash.chevron.right", urlString: "https://github.com"),
        StartPageShortcut(id: "starrail-cloud", title: "云星穹铁道", systemImage: "cloud.fill", urlString: "https://sr.mihoyo.com/cloud/")
    ]
}

private struct QuickActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                Text(title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground).opacity(0.72))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }
}

private struct SectionCard<Content: View>: View {
    let header: String
    var headerTrailing: String?
    let headerAction: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(header)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let headerTrailing {
                    Button(action: headerAction) {
                        Label(headerTrailing, systemImage: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            content
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground).opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }
}

private struct HomeActionCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let badge: String?

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(tint.opacity(0.14))
                    .frame(width: 44, height: 44)
                Image(systemName: systemImage)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let badge {
                Text(badge)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.10), in: Capsule())
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground).opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
        .contentShape(Rectangle())
    }
}
