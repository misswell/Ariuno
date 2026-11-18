import SwiftUI
import UIKit
import WebKit

struct BrowserView: View {
    @EnvironmentObject private var coordinator: AppCoordinator

    @State private var toolbarVisible = true
    @State private var autoHideWorkItem: DispatchWorkItem?
    @State private var activeSheet: GameSheet?
    @State private var showExitConfirmation = false
    @State private var activeAlert: GameAlert?
    @State private var addressText = ""
    @State private var isBallMode = false
    @State private var showFullscreenMenu = false
    @State private var isEditingAddress = false
    @FocusState private var addressFieldFocused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            if isBallMode {
                webContent
                    .ignoresSafeArea()
            } else {
                // Safari-like non-fullscreen layout: the chrome takes its own space below the
                // page instead of overlaying it. The page only becomes edge-to-edge after the
                // user explicitly collapses the toolbar to the floating ball.
                VStack(spacing: 0) {
                    ZStack {
                        webContent
                        if addressFieldFocused {
                            // One row always: the first page tap just dismisses the keyboard.
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture { addressFieldFocused = false }
                                .accessibilityHidden(true)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    chromeBar
                }
                .ignoresSafeArea(edges: .top)
                .transition(.opacity)
            }

            if shouldShowLoadingOverlay {
                loadingOverlay
            }

            if isBallMode {
                GeometryReader { proxy in
                    FloatingEdgeControl(
                        containerSize: proxy.size,
                        normalizedPosition: CGPoint(
                            x: coordinator.settings.floatingBallX,
                            y: coordinator.settings.floatingBallY
                        ),
                        preferredEdge: FloatingBallGeometry.Edge(
                            rawValue: coordinator.settings.floatingBallEdge
                        ),
                        diameter: CGFloat(coordinator.settings.floatingBallDiameter),
                        tint: .accentColor,
                        icon: nil,
                        showsCenterDot: true,
                        showsPiPBadge: coordinator.isAnyPiPActive,
                        accessibilityLabel: "全屏菜单",
                        onTap: { showFullscreenMenu = true },
                        onMoved: { normalized in
                            coordinator.settings.floatingBallX = Double(normalized.x)
                            coordinator.settings.floatingBallY = Double(normalized.y)
                        },
                        onEdgeChanged: { edge in
                            coordinator.settings.floatingBallEdge = edge.rawValue
                        }
                    )
                }
                .transition(.scale.combined(with: .opacity))
            }

        }
        .confirmationDialog(
            "全屏菜单",
            isPresented: $showFullscreenMenu,
            titleVisibility: .visible
        ) {
            Button("退出全屏") {
                expandToolbarFromBall()
            }
            if coordinator.browser.canGoForward {
                Button("前进") {
                    coordinator.browser.goForward()
                }
            }
            Button("刷新页面") {
                coordinator.browser.reload()
            }
            Button("书签") {
                activeSheet = .bookmarks
            }
            Button("历史记录") {
                activeSheet = .history
            }
            Button("下载") {
                activeSheet = .downloads
            }
            Button("主页") {
                coordinator.openHome()
            }
            Button("退出会话", role: .destructive) {
                showExitConfirmation = true
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("当前为全屏模式")
        }
        .statusBarHidden(coordinator.route == .game)
        .onAppear {
            syncAddressText()
            if coordinator.route == .game, coordinator.settings.collapseToolbarToBallOnOpen {
                isBallMode = true
            }
            if coordinator.settings.autoHideToolbar {
                scheduleAutoHide()
            }
        }
        .onDisappear {
            autoHideWorkItem?.cancel()
        }
        .onChange(of: coordinator.route) { _, newRoute in
            guard newRoute == .game else { return }
            withAnimation(.easeInOut(duration: 0.18)) {
                toolbarVisible = true
            }
            if coordinator.settings.collapseToolbarToBallOnOpen {
                isBallMode = true
            }
            syncAddressText()
            scheduleAutoHide()
        }
        .onChange(of: coordinator.browser.currentURL?.absoluteString) { _, _ in
            syncAddressText()
        }
        .onChange(of: coordinator.tabs.activeSessionID) { _, _ in
            syncAddressText()
        }
        .onChange(of: coordinator.settings.autoHideToolbar) { _, _ in
            scheduleAutoHide()
        }
        .onChange(of: coordinator.recoveryPrompt) { _, prompt in
            if let prompt {
                activeAlert = .recovery(prompt)
            }
        }
        .onChange(of: coordinator.browser.pendingExternalURL) { _, url in
            if url != nil {
                activeAlert = .externalLink(coordinator.browser.pendingExternalHost)
            }
        }
        .alert(item: $activeAlert) { alert in
            alertContent(for: alert)
        }
        .confirmationDialog(
            "退出会话？",
            isPresented: $showExitConfirmation,
            titleVisibility: .visible
        ) {
            Button("退出会话", role: .destructive) {
                coordinator.exitSession()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将停止当前标签页并关闭画中画。登录 Cookie 与网站数据会保留，除非你在设置中清除。")
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .diagnostics:
                NavigationStack {
                    DiagnosticsView()
                }
            case .capability:
                PiPCapabilityView()
            case .status:
                PiPStatusSheet()
            case .tabs:
                TabsView()
            case .bookmarks:
                BookmarksView(canAddCurrentPage: true)
            case .history:
                HistoryView()
            case .downloads:
                DownloadsView()
            }
        }
    }

    private var webContent: some View {
        GeometryReader { proxy in
            let insets = contentInsets
            let width = max(1, proxy.size.width - insets.leading - insets.trailing)
            let height = max(1, proxy.size.height - insets.top - insets.bottom)
            BrowserTabHostView(
                sessions: coordinator.tabs.sessions,
                activeSessionID: coordinator.tabs.activeSessionID
            )
            .frame(width: width, height: height)
            .position(x: insets.leading + width / 2, y: insets.top + height / 2)
        }
    }

    private var chromeBar: some View {
        Group {
            if !toolbarVisible {
                HStack {
                    Spacer()
                    toolbarHandle
                }
                .padding(.trailing, 12)
                .padding(.vertical, 8)
            } else {
                VStack(spacing: 4) {
                    if addressFieldFocused, !addressSuggestions.isEmpty {
                        addressSuggestionList
                    }
                    sessionBanner
                    compactBar
                }
                .padding(.top, 4)
                .padding(.bottom, 8)
            }
        }
        .background(
            LinearGradient(
                colors: [Color(white: 0.09), Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(0.06))
                .frame(height: 0.5)
        }
    }

    // MARK: - Address bar

    private var compactBar: some View {
        HStack(spacing: 8) {
            compactBackButton
            compactAddressPill
            compactTabsButton
            compactMoreButton
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var compactBackButton: some View {
        Button {
            coordinator.browser.goBack()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44)
                .liquidGlassCircle(tint: .white.opacity(0.05), interactive: true)
                .shadow(color: .black.opacity(0.18), radius: 9, y: 3)
        }
        .buttonStyle(.plain)
        .disabled(!coordinator.browser.canGoBack)
        .opacity(coordinator.browser.canGoBack ? 1 : 0.4)
        .accessibilityLabel("后退")
    }

    private var compactAddressPill: some View {
        HStack(spacing: 6) {
            Image(systemName: securityIcon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(securityIcon == "globe" ? .orange : .secondary)

            if isEditingAddress {
                TextField("搜索或输入网址", text: $addressText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .submitLabel(.go)
                    .focused($addressFieldFocused)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .onSubmit { openAddress() }
                    .onAppear {
                        DispatchQueue.main.async {
                            addressFieldFocused = true
                        }
                    }
                    .onChange(of: addressFieldFocused) { _, focused in
                        if !focused {
                            isEditingAddress = false
                        }
                    }
                if !addressText.isEmpty {
                    Button {
                        addressText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清空地址栏")
                }
            } else {
                Button {
                    isEditingAddress = true
                } label: {
                    Text(compactAddressText)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("地址栏，点击编辑")
            }

            Button {
                if coordinator.browser.isLoading {
                    coordinator.browser.stop()
                } else {
                    coordinator.browser.reload()
                }
            } label: {
                Image(systemName: coordinator.browser.isLoading ? "xmark" : "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(coordinator.browser.isLoading ? "停止加载" : "重新加载")
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .liquidGlassCapsule(tint: .white.opacity(0.05))
        .shadow(color: .black.opacity(0.18), radius: 9, y: 3)
    }

    private var compactTabsButton: some View {
        Button {
            activeSheet = .tabs
        } label: {
            Image(systemName: "square.on.square")
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 44, height: 44)
                .liquidGlass(cornerRadius: 14, tint: .white.opacity(0.05), interactive: true)
                .shadow(color: .black.opacity(0.18), radius: 9, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("标签页，共 \(coordinator.tabs.sessions.count) 个")
    }

    private var compactMoreButton: some View {
        Menu {
            Button {
                collapseToolbarToBall()
            } label: {
                Label("全屏", systemImage: "arrow.up.left.and.arrow.down.right")
            }
            Button {
                guard let url = coordinator.browser.currentURL,
                      url.absoluteString != "about:blank" else { return }
                coordinator.bookmarks.add(
                    title: coordinator.browser.pageTitle,
                    url: url
                )
                coordinator.showToast("已添加书签", .info)
            } label: {
                Label("添加书签", systemImage: "bookmark")
            }
            .disabled(coordinator.browser.isShowingBlankPage)
            if let url = coordinator.browser.currentURL,
               url.absoluteString != "about:blank" {
                ShareLink(item: url) {
                    Label("分享当前网页", systemImage: "square.and.arrow.up")
                }
            }
            Divider()
            if coordinator.browser.canGoForward {
                Button {
                    coordinator.browser.goForward()
                } label: {
                    Label("前进", systemImage: "chevron.right")
                }
            }
            Divider()
            Button {
                activeSheet = .bookmarks
            } label: {
                Label("书签", systemImage: "book")
            }
            Button {
                activeSheet = .history
            } label: {
                Label("历史记录", systemImage: "clock")
            }
            Button {
                activeSheet = .downloads
            } label: {
                Label("下载", systemImage: "arrow.down.circle")
            }
            Divider()
            Button {
                coordinator.openHome()
            } label: {
                Label("主页", systemImage: "house")
            }
            Button(role: .destructive) {
                showExitConfirmation = true
            } label: {
                Label("退出会话", systemImage: "xmark.circle")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44)
                .liquidGlass(cornerRadius: 14, tint: .white.opacity(0.05), interactive: true)
                .shadow(color: .black.opacity(0.18), radius: 9, y: 3)
        }
        .accessibilityLabel("更多操作")
    }

    private var addressSuggestions: [AddressSuggestion] {
        guard !coordinator.browser.isPrivate else { return [] }
        return AddressSuggestionProvider.suggestions(
            query: addressText,
            history: coordinator.library.history.entries,
            bookmarks: coordinator.bookmarks.bookmarks
        )
    }

    private var addressSuggestionList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(addressSuggestions) { suggestion in
                    Button {
                        addressText = suggestion.urlString
                        openAddress()
                    } label: {
                        AddressSuggestionRow(suggestion: suggestion)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        "\(suggestion.kind == .bookmark ? "书签" : "历史记录")，\(suggestion.displayTitle)，\(suggestion.displayHost)"
                    )
                    if suggestion.id != addressSuggestions.last?.id {
                        Divider().opacity(0.35)
                    }
                }
            }
        }
        .frame(maxHeight: 210)
        .liquidGlass(cornerRadius: 16, tint: .accentColor.opacity(0.05))
        .padding(.horizontal, 12)
    }

    private var compactAddressText: String {
        if let host = coordinator.browser.currentHost, !host.isEmpty {
            return host
        }
        if let url = coordinator.browser.currentURL, url.absoluteString != "about:blank" {
            return url.absoluteString
        }
        return "搜索或输入网址"
    }

    private var tabsBarButton: some View {
        Button {
            activeSheet = .tabs
        } label: {
            Image(systemName: "square.on.square")
                .font(.system(size: 16, weight: .semibold))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("标签页，共 \(coordinator.tabs.sessions.count) 个")
    }

    private var isScreenshotMode: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-CFScreenshotMode")
        #else
        return false
        #endif
    }

    private var contentInsets: EdgeInsets {
        EdgeInsets(
            top: coordinator.settings.fullscreenInsetTop,
            leading: coordinator.settings.fullscreenInsetLeft,
            bottom: coordinator.settings.fullscreenInsetBottom,
            trailing: coordinator.settings.fullscreenInsetRight
        )
    }

    private var securityIcon: String {
        if let url = coordinator.browser.currentURL, url.scheme?.lowercased() == "https" {
            return "lock.fill"
        }
        return "globe"
    }

    private var toolbarHandle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                toolbarVisible = true
            }
            scheduleAutoHide()
        } label: {
            HStack(spacing: 5) {
                Capsule()
                    .fill(Color.white.opacity(0.42))
                    .frame(width: 34, height: 4)
                if !pipAvailability.isAvailable, !coordinator.session.pipVisible {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 4, height: 4)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .liquidGlassCapsule(tint: .white.opacity(0.04), interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("显示工具栏")
    }

    // MARK: - Banners

    @ViewBuilder
    private var sessionBanner: some View {
        if let failure = coordinator.browser.lastNavigationFailure,
           coordinator.session.state == .failed {
            GameBanner(
                title: "页面加载失败",
                message: TLSErrorClassifier.userMessage(for: failure),
                primaryTitle: "重新加载",
                onPrimary: { coordinator.requestUserReload() },
                onDiagnostics: { activeSheet = .diagnostics }
            )
        } else if coordinator.session.state == .failed {
            GameBanner(
                title: "页面进程异常",
                message: coordinator.session.failureReason ?? "需要你确认后才能恢复页面。",
                primaryTitle: "恢复",
                onPrimary: { coordinator.requestUserReload() },
                onDiagnostics: { activeSheet = .diagnostics }
            )
        } else if coordinator.session.state == .streamStalled {
            GameBanner(
                title: "画面停滞",
                message: "视频已长时间没有进展。App 不会自动重连，避免重复启动云游戏会话。",
                primaryTitle: "手动重试",
                onPrimary: { coordinator.requestUserReload() },
                onDiagnostics: { activeSheet = .diagnostics }
            )
        } else if coordinator.session.state == .disconnected {
            GameBanner(
                title: "连接中断",
                message: "网络不可用或媒体连接已断开。等待网络恢复后可手动重试。",
                primaryTitle: "重试",
                onPrimary: { coordinator.requestUserReload() },
                onDiagnostics: { activeSheet = .diagnostics }
            )
        }
    }

    private var loadingOverlay: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
                .tint(.white)
            Text("正在加载页面")
                .font(.headline)
                .foregroundStyle(.white)
            Text("登录与网页内容均在官方网站内完成\nAriuno 不接触账号密码或令牌")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.72))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.55))
        .allowsHitTesting(false)
    }

    // MARK: - PiP

    // MARK: - Actions

    private func openAddress() {
        addressFieldFocused = false
        coordinator.openAddressText(addressText)
        syncAddressText()
    }

    private func syncAddressText() {
        guard !addressFieldFocused else { return }
        addressText = coordinator.browser.currentURL?.absoluteString ?? ""
    }

    private func collapseToolbarToBall() {
        addressFieldFocused = false
        autoHideWorkItem?.cancel()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            isBallMode = true
        }
    }

    private func expandToolbarFromBall() {
        autoHideWorkItem?.cancel()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            isBallMode = false
            toolbarVisible = true
        }
    }

    private func scheduleAutoHide() {
        autoHideWorkItem?.cancel()
        guard coordinator.settings.autoHideToolbar else { return }
        let item = DispatchWorkItem {
            withAnimation(.easeInOut(duration: 0.2)) {
                toolbarVisible = false
            }
        }
        autoHideWorkItem = item
        DispatchQueue.main.asyncAfter(
            deadline: .now() + coordinator.settings.toolbarAutoHideDelay,
            execute: item
        )
    }

    private func alertContent(for alert: GameAlert) -> Alert {
        switch alert {
        case .recovery(let prompt):
            return Alert(
                title: Text(prompt.title),
                message: Text(prompt.message),
                primaryButton: .default(Text(prompt.confirmTitle)) {
                    coordinator.confirmRecovery()
                },
                secondaryButton: .cancel(Text("取消")) {
                    coordinator.dismissRecoveryPrompt()
                }
            )
        case .externalLink(let host):
            return Alert(
                title: Text("打开外部链接？"),
                message: Text("目标：\(host)。链接将在系统浏览器中打开，不会在应用内执行。"),
                primaryButton: .default(Text("在系统浏览器打开")) {
                    coordinator.confirmExternalOpen()
                },
                secondaryButton: .cancel(Text("取消")) {
                    coordinator.cancelExternalOpen()
                }
            )
        case .pipFailure(let message):
            return Alert(
                title: Text("无法进入画中画"),
                message: Text(message),
                dismissButton: .default(Text("知道了"))
            )
        }
    }

    // MARK: - Derived state

    private var pipAvailability: PiPAvailability {
        coordinator.pip.availability
    }

    private var shouldShowLoadingOverlay: Bool {
        coordinator.browser.isLoading
            && !coordinator.browser.hasCommittedPage
            && coordinator.media.lastSnapshotReceivedAt == nil
    }
}

private enum GameSheet: Identifiable {
    case diagnostics
    case capability
    case status
    case tabs
    case bookmarks
    case history
    case downloads

    var id: String {
        switch self {
        case .diagnostics: return "diagnostics"
        case .capability: return "capability"
        case .status: return "status"
        case .tabs: return "tabs"
        case .bookmarks: return "bookmarks"
        case .history: return "history"
        case .downloads: return "downloads"
        }
    }
}

private enum GameAlert: Identifiable {
    case recovery(RecoveryPrompt)
    case externalLink(String)
    case pipFailure(String)

    var id: String {
        switch self {
        case .recovery(let prompt): return "recovery-\(prompt.id.uuidString)"
        case .externalLink(let host): return "external-\(host)"
        case .pipFailure(let message): return "pip-\(message.hashValue)"
        }
    }
}

private struct GameBanner: View {
    let title: String
    let message: String
    let primaryTitle: String
    let onPrimary: () -> Void
    let onDiagnostics: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.orange)
                Text(title)
                    .font(.footnote.weight(.semibold))
                Spacer()
            }
            Text(message)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button(primaryTitle, action: onPrimary)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button("诊断", action: onDiagnostics)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Spacer()
            }
        }
        .padding(12)
        .liquidGlass(cornerRadius: 16, tint: .orange.opacity(0.05))
        .padding(.horizontal, 12)
    }
}
