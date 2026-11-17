import SwiftUI
import UIKit
import WebKit

struct BrowserView: View {
    @EnvironmentObject private var coordinator: AppCoordinator

    @State private var toolbarVisible = true
    @State private var autoHideWorkItem: DispatchWorkItem?
    @State private var activeSheet: GameSheet?
    @State private var showExitConfirmation = false
    @State private var isPiPRequestInFlight = false
    @State private var activeAlert: GameAlert?
    @State private var addressText = ""
    @State private var isBallMode = false
    @FocusState private var addressFieldFocused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

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
            .ignoresSafeArea()

            if shouldShowLoadingOverlay {
                loadingOverlay
            }

            if !isBallMode {
                VStack(spacing: 8) {
                    Spacer(minLength: 0)
                    sessionBanner
                    if toolbarVisible {
                        addressBar
                            .padding(.horizontal, 12)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        // The reveal control stays on the trailing edge instead of floating in
                        // the middle of the page, so it is easy to find without covering content.
                        HStack {
                            Spacer()
                            toolbarHandle
                        }
                        .padding(.trailing, 12)
                    }
                    bottomBar
                        .padding(.horizontal, 12)
                }
                .padding(.top, 6)
                .padding(.bottom, 8)
                .transition(.opacity)
            }

            if isBallMode {
                GeometryReader { proxy in
                    FloatingEdgeControl(
                        containerSize: proxy.size,
                        normalizedPosition: CGPoint(
                            x: coordinator.settings.floatingBallX,
                            y: coordinator.settings.floatingBallY
                        ),
                        diameter: CGFloat(coordinator.settings.floatingBallDiameter),
                        tint: .accentColor,
                        icon: nil,
                        showsCenterDot: true,
                        showsPiPBadge: coordinator.isAnyPiPActive,
                        accessibilityLabel: "展开工具栏",
                        onTap: { expandToolbarFromBall() },
                        onMoved: { normalized in
                            coordinator.settings.floatingBallX = Double(normalized.x)
                            coordinator.settings.floatingBallY = Double(normalized.y)
                        }
                    )
                }
                .transition(.scale.combined(with: .opacity))
            }

            if coordinator.settings.showFloatingPiPButton,
               coordinator.isAnyPiPActive || pipAvailability.isAvailable {
                GeometryReader { proxy in
                    FloatingEdgeControl(
                        containerSize: proxy.size,
                        normalizedPosition: CGPoint(
                            x: coordinator.settings.floatingPiPX,
                            y: coordinator.settings.floatingPiPY
                        ),
                        diameter: CGFloat(coordinator.settings.floatingBallDiameter) * 0.84,
                        tint: coordinator.isAnyPiPActive ? .green : .accentColor,
                        icon: "pip",
                        showsCenterDot: false,
                        showsPiPBadge: false,
                        accessibilityLabel: coordinator.isAnyPiPActive
                            ? "退出画中画" : "进入画中画",
                        onTap: { togglePiPFromFloatingControl() },
                        onMoved: { normalized in
                            coordinator.settings.floatingPiPX = Double(normalized.x)
                            coordinator.settings.floatingPiPY = Double(normalized.y)
                        }
                    )
                }
                .transition(.scale.combined(with: .opacity))
            }
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

    // MARK: - Address bar

    private var addressBar: some View {
        VStack(spacing: 6) {
            if coordinator.browser.estimatedProgress < 0.995 {
                ProgressView(value: coordinator.browser.estimatedProgress)
                    .progressViewStyle(.linear)
                    .tint(.accentColor)
                    .padding(.horizontal, 2)
            }

            if !addressFieldFocused, !coordinator.browser.displayTitle.isEmpty {
                Text(coordinator.browser.displayTitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }

            HStack(spacing: 8) {
                if coordinator.browser.isPrivate {
                    Label("隐私", systemImage: "mask")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                }

                navigationButton(
                    systemName: "chevron.left",
                    accessibilityLabel: "后退",
                    disabled: !coordinator.browser.canGoBack
                ) {
                    coordinator.browser.goBack()
                }
                navigationButton(
                    systemName: "chevron.right",
                    accessibilityLabel: "前进",
                    disabled: !coordinator.browser.canGoForward
                ) {
                    coordinator.browser.goForward()
                }

                HStack(spacing: 6) {
                    Image(systemName: securityIcon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(securityIcon == "globe" ? .orange : .secondary)
                    if let url = coordinator.browser.currentURL,
                       url.scheme?.lowercased() == "http" {
                        Text("不安全")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.orange)
                    }
                    TextField(
                        "搜索或输入网址",
                        text: $addressText
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .submitLabel(.go)
                    .focused($addressFieldFocused)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .onSubmit {
                        openAddress()
                    }
                    if addressFieldFocused, !addressText.isEmpty {
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
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .frame(maxWidth: .infinity)
                .contextMenu {
                    if let url = coordinator.browser.currentURL,
                       url.absoluteString != "about:blank" {
                        Button {
                            UIPasteboard.general.string = url.absoluteString
                            coordinator.showToast("已复制网址", .info)
                        } label: {
                            Label("复制网址", systemImage: "doc.on.doc")
                        }
                    }
                    Button {
                        if let value = UIPasteboard.general.string, !value.isEmpty {
                            addressText = value
                            addressFieldFocused = true
                        }
                    } label: {
                        Label("粘贴", systemImage: "doc.on.clipboard")
                    }
                    Button {
                        addressText = ""
                        addressFieldFocused = true
                    } label: {
                        Label("清空输入", systemImage: "xmark.circle")
                    }
                }

                navigationButton(
                    systemName: coordinator.browser.isLoading ? "xmark" : "arrow.clockwise",
                    accessibilityLabel: coordinator.browser.isLoading ? "停止加载" : "重新加载",
                    disabled: false
                ) {
                    if coordinator.browser.isLoading {
                        coordinator.browser.stop()
                    } else {
                        coordinator.browser.reload()
                    }
                }
                navigationButton(
                    systemName: "square.on.square",
                    accessibilityLabel: "标签页",
                    disabled: false
                ) {
                    activeSheet = .tabs
                }
            }

            if !isScreenshotMode, !pipAvailability.isAvailable, !coordinator.session.pipVisible,
               let reason = pipAvailability.reason {
                HStack(spacing: 5) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 9, weight: .semibold))
                    Text(reason.userMessage)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.orange)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(.horizontal, 2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
    }

    private var bottomBar: some View {
        HStack(spacing: 20) {
            Button {
                guard let url = coordinator.browser.currentURL,
                      url.absoluteString != "about:blank" else { return }
                coordinator.bookmarks.add(
                    title: coordinator.browser.pageTitle,
                    url: url
                )
                coordinator.showToast("已添加书签", .info)
            } label: {
                Image(systemName: "bookmark")
                    .font(.system(size: 16, weight: .semibold))
            }
            .buttonStyle(.plain)
            .disabled(coordinator.browser.isShowingBlankPage)
            .accessibilityLabel("添加书签")

            if let url = coordinator.browser.currentURL,
               url.absoluteString != "about:blank" {
                ShareLink(item: url) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                }
                .accessibilityLabel("分享当前网页")
            }

            Spacer(minLength: 0)

            Button {
                activeSheet = .bookmarks
            } label: {
                Image(systemName: "book")
                    .font(.system(size: 16, weight: .semibold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("书签")

            Button {
                activeSheet = .tabs
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "square.on.square")
                        .font(.system(size: 16, weight: .semibold))
                    Text("\(coordinator.tabs.sessions.count)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.accentColor, in: Capsule())
                        .offset(x: 9, y: -7)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("标签页，共 \(coordinator.tabs.sessions.count) 个")

            Button {
                collapseToolbarToBall()
            } label: {
                Image(systemName: "rectangle.compress.vertical")
                    .font(.system(size: 16, weight: .semibold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("收起为悬浮球")

            Menu {
                Button {
                    activeSheet = .status
                } label: {
                    Label("会话状态", systemImage: "square.stack.3d.up")
                }
                Button {
                    activeSheet = .capability
                } label: {
                    Label("画中画能力检测", systemImage: "pip")
                }
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
                Button {
                    activeSheet = .diagnostics
                } label: {
                    Label("诊断", systemImage: "waveform.path.ecg")
                }
                Divider()
                Button {
                    coordinator.openHome()
                } label: {
                    Label("主页", systemImage: "house")
                }
                Button {
                    coordinator.requestUserReload()
                } label: {
                    Label("重新加载页面", systemImage: "arrow.clockwise")
                }
                Button(role: .destructive) {
                    showExitConfirmation = true
                } label: {
                    Label("退出会话", systemImage: "xmark.circle")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 17, weight: .semibold))
            }
            .accessibilityLabel("更多操作")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        .padding(.bottom, 2)
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

    private func navigationButton(
        systemName: String,
        accessibilityLabel: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 32, height: 32)
                .background(Color.primary.opacity(0.08), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
        .accessibilityLabel(accessibilityLabel)
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
            .background(Color.black.opacity(0.22), in: Capsule())
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

    private func attemptPiP() async {
        guard !isPiPRequestInFlight else { return }
        isPiPRequestInFlight = true
        let outcome = await coordinator.requestPictureInPicture()
        isPiPRequestInFlight = false

        switch outcome {
        case .success:
            coordinator.showToast("已进入系统画中画", .info)
        case .failure(let reason, _):
            var message = reason.userMessage
            if reason == .requiresUserGesture {
                message += "\n\n请点击网页视频画面右上角的 PiP 按钮。若没有看到按钮，请在设置中开启“显示网页内 PiP 按钮”，并让视频重新加载后重试；WebKit 只接受来自网页内容的真实点击。"
            }
            if reason == .platformUnsupported {
                message += "\n\n请使用真实 iPhone 验证；模拟器不支持系统画中画。"
            }
            activeAlert = .pipFailure(message)
        }
    }

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

    private func togglePiPFromFloatingControl() {
        if coordinator.isAnyPiPActive || coordinator.session.pipVisible {
            coordinator.exitPictureInPicture()
            return
        }
        Task { @MainActor in
            await attemptPiP()
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
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 12)
    }
}
