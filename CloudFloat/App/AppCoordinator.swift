import Combine
import Foundation
import SwiftUI
import UIKit

enum AppRoute: Equatable {
    case home
    case game
}

enum DebugPresentation: String, Identifiable {
    case testLab
    case diagnostics
    case settings
    case capability

    var id: String { rawValue }
}

struct RecoveryPrompt: Identifiable, Equatable {
    let id: UUID
    let trigger: RecoveryTrigger
    let title: String
    let message: String
    let confirmTitle: String

    init(
        id: UUID = UUID(),
        trigger: RecoveryTrigger,
        title: String,
        message: String,
        confirmTitle: String
    ) {
        self.id = id
        self.trigger = trigger
        self.title = title
        self.message = message
        self.confirmTitle = confirmTitle
    }
}

enum ToastKind: Equatable {
    case info
    case warning
    case error
}

struct ToastMessage: Identifiable, Equatable {
    let id: UUID
    let text: String
    let kind: ToastKind

    init(id: UUID = UUID(), text: String, kind: ToastKind) {
        self.id = id
        self.text = text
        self.kind = kind
    }
}

struct PiPCapabilityReport: Identifiable, Equatable {
    let id: UUID
    let generatedAt: Date
    let platformSupportsPiP: Bool
    let webViewAllowsPiP: Bool
    let probeScriptLoaded: Bool
    let hasProbeSnapshot: Bool
    let aggregate: MediaAggregate
    let availability: PiPAvailability
    let pageHost: String?
    let sessionState: GameSessionState
    let nativePipelineStatus: NativeMediaPipelineStatus
    let isSimulator: Bool
    let notes: [String]

    init(
        id: UUID = UUID(),
        generatedAt: Date,
        platformSupportsPiP: Bool,
        webViewAllowsPiP: Bool,
        probeScriptLoaded: Bool,
        hasProbeSnapshot: Bool,
        aggregate: MediaAggregate,
        availability: PiPAvailability,
        pageHost: String?,
        sessionState: GameSessionState,
        nativePipelineStatus: NativeMediaPipelineStatus,
        isSimulator: Bool,
        notes: [String]
    ) {
        self.id = id
        self.generatedAt = generatedAt
        self.platformSupportsPiP = platformSupportsPiP
        self.webViewAllowsPiP = webViewAllowsPiP
        self.probeScriptLoaded = probeScriptLoaded
        self.hasProbeSnapshot = hasProbeSnapshot
        self.aggregate = aggregate
        self.availability = availability
        self.pageHost = pageHost
        self.sessionState = sessionState
        self.nativePipelineStatus = nativePipelineStatus
        self.isSimulator = isSimulator
        self.notes = notes
    }

    var verdictTitle: String {
        if !platformSupportsPiP { return "当前设备不支持系统画中画" }
        if !webViewAllowsPiP { return "WebView 未启用画中画" }
        if !probeScriptLoaded { return "媒体探测脚本缺失" }
        if !hasProbeSnapshot { return "尚未收到媒体探测数据" }
        if let reason = availability.reason { return reason.userMessage }
        return "系统画中画可用"
    }

    var verdictDetail: String {
        if let reason = availability.reason {
            return reason.userMessage
        }
        if availability.isAvailable {
            return "检测到正在播放且支持 HTML5 PiP 的视频。仍需在网页内点击 PiP 控件（或由原生按钮触发并处理用户激活失败）。"
        }
        return "未知状态，请重新检测。"
    }
}

/// Top-level composition root. Owns the stable browser session and wires observations into
/// the session state machine, diagnostics and PiP coordinator. It never reloads automatically.
@MainActor
final class AppCoordinator: ObservableObject {
    let settings: AppSettings
    let diagnostics: DiagnosticsStore
    let tabs: BrowserTabManager
    let bookmarks: BookmarkStore
    let session: SessionMonitor
    let network: NetworkObserver
    let recovery: WebContentRecovery
    let audioSession: AudioSessionManager
    let pipManager: PiPManager
    let library: BrowserLibraryStore

    var browser: BrowserSession { tabs.activeSession }
    /// Shared across every tab; owned by the tab manager so downloads survive tab switches.
    var downloadManager: DownloadManager { tabs.downloadManager }
    var media: MediaDetector { browser.mediaDetector }
    var pip: WebPictureInPictureCoordinator { pipManager.coordinator(for: browser) }
    var cookieStore: CookieStore { browser.cookieStore }

    @Published var route: AppRoute = .home
    @Published private(set) var hasStartedBrowser = false
    @Published var recoveryPrompt: RecoveryPrompt?
    @Published private(set) var toast: ToastMessage?
    @Published private(set) var isClearingWebsiteData = false
    @Published private(set) var websiteDataError: String?
    /// Debug/QA entry point for launch-argument driven screenshots and manual checks. The
    /// settings are only applied from launch arguments in DEBUG builds.
    @Published var debugPresentation: DebugPresentation?

    #if DEBUG
    private var debugLocalGameServer: LocalHTTPServer?
    #endif

    private var cancellables = Set<AnyCancellable>()
    private var toastTask: Task<Void, Never>?
    private var pendingPiPCloseTasks: [UUID: Task<Void, Never>] = [:]
    private var lastSnapshotSignature = ""
    private var lastNetworkStatus: NetworkStatus = .unknown

    init(
        settings: AppSettings,
        diagnostics: DiagnosticsStore,
        recentlyClosed: RecentlyClosedStore? = nil,
        tabPersistence: TabSessionStore? = nil
    ) {
        self.settings = settings
        self.diagnostics = diagnostics

        let policy = NavigationPolicy(
            allowsLocalTestPages: settings.allowLocalTestPages && FeatureFlags.localTestServerEnabled,
            localTestPorts: [],
            allowedFileDirectory: Bundle.main.resourceURL?.appendingPathComponent("TestPages")
        )
        self.tabs = BrowserTabManager(
            navigationPolicy: policy,
            inPageControlEnabled: settings.enableInPagePiPButton,
            recentlyClosed: recentlyClosed,
            persistence: tabPersistence
        )
        self.bookmarks = BookmarkStore()
        self.session = SessionMonitor()
        self.network = NetworkObserver()
        self.recovery = WebContentRecovery()
        self.audioSession = AudioSessionManager()
        self.pipManager = PiPManager()
        self.library = BrowserLibraryStore()

        wire()
        configure(tabs.activeSession)
        start()

        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-CFOpenTestLab") {
            debugPresentation = .testLab
        } else if arguments.contains("-CFOpenDiagnostics") {
            debugPresentation = .diagnostics
        } else if arguments.contains("-CFOpenSettings") {
            debugPresentation = .settings
        } else if arguments.contains("-CFOpenCapability") {
            debugPresentation = .capability
        }
        if arguments.contains("-CFOpenLocalGame") {
            Task { @MainActor in
                await self.openDebugLocalPage()
            }
        }
        if arguments.contains("-CFOpenBrowser") {
            continueBrowsing()
        }
        #endif
    }

    // MARK: - Lifecycle

    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .background:
            diagnostics.info(.app, "scene.background", "进入后台；保留 WebView，不自动重载")
            session.appDidEnterBackground()
            if let source = pipManager.activePiPTabID {
                diagnostics.info(
                    .pip,
                    "pip.background_retained",
                    "进入后台时 PiP 来源保持不变",
                    ["source": Self.shortTabID(source)]
                )
            }
            // Persist tab metadata before suspension; PiP source tabs are left untouched.
            tabs.savePersistedStateNow()
            updateMediaScheduling()
            updateAudioSession()
        case .active:
            diagnostics.info(.app, "scene.active", "回到前台；继续使用现有页面")
            session.appDidBecomeActive()
            if let source = pipManager.activePiPTabID {
                diagnostics.info(
                    .pip,
                    "pip.foreground_retained",
                    "回到前台时 PiP 来源保持不变",
                    ["source": Self.shortTabID(source)]
                )
            }
            if hasStartedBrowser {
                updateMediaScheduling()
                browser.verifyExistingPageOnForeground()
            }
            pip.refreshAvailability()
            updateAudioSession()
        case .inactive:
            break
        @unknown default:
            break
        }
    }

    // MARK: - Navigation

    func continueBrowsing() {
        route = .game
        hasStartedBrowser = true
        if browser.resumeRestoredPageIfNeeded() {
            diagnostics.info(.app, "session.continue", "恢复上次会话的标签页")
        } else if browser.isShowingBlankPage {
            browser.loadURL(URLInputParser.placeholderURL())
            diagnostics.info(.app, "session.continue", "打开新标签页")
        } else {
            browser.verifyExistingPageOnForeground()
            diagnostics.info(.app, "session.continue", "继续使用已加载的页面")
        }
        updateMediaScheduling()
    }

    func openURL(_ url: URL) {
        route = .game
        hasStartedBrowser = true
        browser.loadURL(url)
        updateMediaScheduling()
        session.resetForTabSwitch(hasLoadedPage: false)
        diagnostics.info(
            .navigation,
            "nav.open",
            "打开用户输入的地址",
            ["host": url.host ?? ""]
        )
    }

    func openAddressText(_ text: String) {
        if let url = URLInputParser.url(from: text) {
            openURL(url)
            return
        }
        guard let url = settings.searchEngine.searchURL(for: text) else {
            showToast("请输入有效的网址", .warning)
            return
        }
        openURL(url)
    }

    func activateTab(_ tabSession: BrowserSession) {
        let pipSourceBeforeSwitch = pipManager.activePiPTabID
        tabs.activateTab(tabSession)
        session.resetForTabSwitch(hasLoadedPage: tabSession.hasLoadedPage)
        route = .game
        hasStartedBrowser = true
        tabSession.resumeRestoredPageIfNeeded()
        updateMediaScheduling()
        if let source = pipSourceBeforeSwitch, source != tabSession.id {
            diagnostics.info(
                .pip,
                "pip.tab_switch_source_retained",
                "切换标签后 PiP 来源保持不变",
                [
                    "source": Self.shortTabID(source),
                    "active": Self.shortTabID(tabSession.id)
                ]
            )
        }
    }

    enum TabCloseResult {
        case closed
        case requiresPiPConfirmation
    }

    @discardableResult
    func closeTab(_ tabSession: BrowserSession, force: Bool = false) -> TabCloseResult {
        if pipManager.isPiPActive(for: tabSession) {
            guard force else {
                showToast("该标签页正在画中画。请先退出 PiP，或确认关闭以结束浮窗。", .warning)
                return .requiresPiPConfirmation
            }
            // Correct order: ask the system to stop PiP first, keep the WebView alive, and only
            // tear the tab down once the page reports it left PiP (or a short timeout fires).
            beginDeferredPiPClose(tabSession)
            return .closed
        }
        let outcome = tabs.closeTab(tabSession, force: force)
        switch outcome {
        case .closed:
            finishTabClose(tabSession)
            return .closed
        case .requiresPiPConfirmation:
            showToast("该标签页正在画中画。请先退出 PiP，或确认关闭以结束浮窗。", .warning)
            return .requiresPiPConfirmation
        }
    }

    /// Closes several tabs using an ID snapshot. Safe against index shifting.
    @discardableResult
    func closeTabs(withIDs ids: [UUID], force: Bool = false) -> TabCloseResult {
        let sessions = ids.compactMap { tabs.session(withID: $0) }
        let protected = sessions.filter { pipManager.isPiPActive(for: $0) }
        if !force, !protected.isEmpty {
            showToast("有标签页正在画中画；请先退出 PiP 或确认关闭", .warning)
            return .requiresPiPConfirmation
        }
        if force, !protected.isEmpty {
            for session in protected {
                beginDeferredPiPClose(session)
            }
            let remaining = sessions.filter { !pipManager.isPiPActive(for: $0) }
            _ = tabs.closeTabs(withIDs: remaining.map(\.id), force: true)
            remaining.forEach(finishTabClose)
            return .closed
        }
        _ = tabs.closeTabs(withIDs: ids, force: force)
        sessions.forEach(finishTabClose)
        return .closed
    }

    private func finishTabClose(_ tabSession: BrowserSession) {
        pendingPiPCloseTasks.removeValue(forKey: tabSession.id)?.cancel()
        pipManager.stopObserving(tabSession)
        TabThumbnailCache.shared.remove(tabID: tabSession.id)
    }

    /// Batch close entry point for the tab UI. Performs PiP/thumbnail cleanup for every
    /// session that actually went away.
    @discardableResult
    func closeAllTabs(except session: BrowserSession? = nil, force: Bool = false) -> Bool {
        let before = tabs.sessions
        let closed = tabs.closeAllTabs(except: session, force: force)
        guard closed else { return false }
        let remaining = Set(tabs.sessions.map(\.id))
        for tabSession in before where !remaining.contains(tabSession.id) {
            finishTabClose(tabSession)
        }
        return true
    }

    // MARK: - Deferred PiP close

    private func beginDeferredPiPClose(_ tabSession: BrowserSession) {
        showToast("已请求结束画中画，正在安全关闭标签页", .info)
        diagnostics.info(
            .pip,
            "pip.close_requested",
            "请求先停止 PiP 再关闭来源标签",
            ["source": Self.shortTabID(tabSession.id)]
        )
        pipManager.beginStopBeforeClose(tabSession)
        pendingPiPCloseTasks.removeValue(forKey: tabSession.id)?.cancel()
        pendingPiPCloseTasks[tabSession.id] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.completeDeferredPiPClose(tabSession)
            }
        }
    }

    /// Called when the page reports `leavepictureinpicture` (or by the timeout fallback).
    func completeDeferredPiPClose(_ tabSession: BrowserSession) {
        guard pipManager.pendingCloseTabIDs.contains(tabSession.id) else { return }
        pipManager.cancelStopBeforeClose(tabSession)
        pendingPiPCloseTasks.removeValue(forKey: tabSession.id)?.cancel()
        pipManager.clearActivePiP(for: tabSession)
        _ = tabs.closeTab(tabSession, force: true)
        finishTabClose(tabSession)
        diagnostics.info(
            .pip,
            "pip.close_completed",
            "收到 PiP 停止事件后已安全关闭来源标签页",
            ["source": Self.shortTabID(tabSession.id)]
        )
    }

    func createTab(url: URL? = nil, isPrivate: Bool = false) {
        let pipSource = pipManager.activePiPTabID
        let newTab = tabs.createTab(url: url, isPrivate: isPrivate)
        // A brand-new tab shows the browser start page; only explicit URLs open web content.
        route = url == nil ? .home : .game
        hasStartedBrowser = true
        updateMediaScheduling()
        if let pipSource {
            diagnostics.info(
                .pip,
                "pip.tab_created_while_active",
                "PiP 播放期间新建标签；来源仍绑定原标签",
                [
                    "source": Self.shortTabID(pipSource),
                    "newTab": Self.shortTabID(newTab.id)
                ]
            )
        }
    }

    /// Returns to the start page without destroying any tab or WebView.
    func openHome() {
        route = .home
        updateMediaScheduling()
    }

    /// Restores the most recently closed tab and opens the browser on it.
    @discardableResult
    func restoreRecentlyClosedTab() -> ClosedTabSnapshot? {
        guard let snapshot = tabs.restoreRecentlyClosed() else { return nil }
        route = .game
        hasStartedBrowser = true
        updateMediaScheduling()
        session.resetForTabSwitch(hasLoadedPage: false)
        diagnostics.info(.navigation, "tab.restore", "已恢复最近关闭的标签页")
        return snapshot
    }

    func backToHome() {
        route = .home
    }

    func exitSession() {
        if pipManager.activePiPTabID != nil {
            pipManager.exitActivePiP()
        }
        browser.resetToBlank()
        session.userExited()
        hasStartedBrowser = false
        route = .home
        updateMediaScheduling()
        recovery.reset()
        audioSession.deactivate()
        diagnostics.info(.app, "session.exit", "用户退出会话；网站数据与登录状态保留")
    }

    // MARK: - Media scheduling

    /// Single source of truth for probe polling. At most two timers exist: the active tab and
    /// the PiP source tab. Every other tab stops polling, so background tabs never run
    /// JavaScript on a timer. Polling also stops entirely while the app is backgrounded.
    private func updateMediaScheduling() {
        let appIsForeground = session.appIsForeground
        let browserActive = hasStartedBrowser && route == .game
        let pipSourceID = pipManager.activePiPTabID
        for tab in tabs.sessions {
            guard !tab.isClosed else {
                tab.mediaDetector.stopPolling()
                continue
            }
            let isActive = browserActive && tab.id == browser.id
            let isPiPSource = tab.id == pipSourceID
            let shouldPoll = appIsForeground && (isActive || isPiPSource)
            if shouldPoll {
                tab.mediaDetector.startPolling()
            } else {
                tab.mediaDetector.stopPolling()
            }
        }
        session.setMediaProbePolling(browser.mediaDetector.isPolling)
    }

    var activelyPollingTabCount: Int {
        tabs.sessions.filter { $0.mediaDetector.isPolling }.count
    }


    func requestPictureInPicture() async -> PiPRequestOutcome {
        session.pipRequestStarted()
        let outcome = await pipManager.requestPiP(for: browser)
        if case .failure(let reason, _) = outcome {
            session.pipRequestFailed(reason: reason)
        }
        return outcome
    }

    func exitPictureInPicture() {
        pipManager.exitPiP(for: browser)
    }

    func makePiPCapabilityReport(refresh: Bool = true) -> PiPCapabilityReport {
        if refresh {
            media.refreshNow()
            pip.refreshAvailability()
        }
        let aggregate = media.aggregate
        return PiPCapabilityReport(
            generatedAt: Date(),
            platformSupportsPiP: pip.platformSupportsPiP,
            webViewAllowsPiP: browser.pictureInPictureAllowedByConfiguration,
            probeScriptLoaded: media.probeScriptLoaded,
            hasProbeSnapshot: media.lastSnapshotReceivedAt != nil,
            aggregate: aggregate,
            availability: pip.availability,
            pageHost: browser.currentHost,
            sessionState: session.state,
            nativePipelineStatus: NativePictureInPictureCoordinator.status,
            isSimulator: Self.isSimulator,
            notes: capabilityNotes(aggregate: aggregate)
        )
    }

    private func capabilityNotes(aggregate: MediaAggregate) -> [String] {
        var notes: [String] = [
            "PiP 已显示 ≠ 媒体仍在实时传输 ≠ 云游戏服务器端会话仍在运行。三层必须分别验证。",
            "服务器会话状态：UNVERIFIED。App 无法通过公开 API 证明自动战斗或游戏进度仍在继续。"
        ]
        if Self.isSimulator {
            notes.append("模拟器通常不支持系统画中画；T01/T03/T04/T05 必须在真实 iPhone 上验证。")
        }
        if !media.probeScriptLoaded {
            notes.append("MediaProbe.js 未加载，无法判断网页媒体能力。")
        } else if media.lastSnapshotReceivedAt == nil {
            notes.append("尚未收到媒体探测快照；请先打开官方页面并让游戏画面开始播放。")
        }
        if aggregate.kind == .canvas {
            notes.append("页面仅检测到 Canvas/WebGL，没有可进入 HTML5 PiP 的 video 元素。")
        }
        if aggregate.kind == .crossOriginFrame {
            notes.append("媒体可能位于跨域 iframe；父页面不能读取子 frame DOM，子 frame 会独立上报探测结果。")
        }
        if aggregate.hasPiPCapablePlayingVideo
            && !aggregate.mainFrameHasPiPCapablePlayingVideo {
            notes.append("可 PiP 的视频位于跨域子 frame。WebKit 不允许父页面跨域调用子 frame 的 PiP，请点击网页内（视频所在 frame）右上角的 PiP 按钮；原生按钮会如实提示需要网页内点击。")
        }
        if let video = aggregate.bestVideo {
            if video.drmProtected {
                notes.append("视频受 DRM/EME 保护，系统 PiP 可能被禁止。")
            }
            if !video.pipSupported {
                notes.append("该视频节点不支持 HTML5 PiP（webkitSupportsPresentationMode 为 false）。")
            }
            if video.pipFeatureAllowed == false {
                notes.append("iframe 的 Permissions Policy 禁止 picture-in-picture。")
            }
        }
        notes.append("M4 原生媒体管线：\(NativePictureInPictureCoordinator.status.displayText)")
        return notes
    }

    // MARK: - Recovery

    func requestUserReload() {
        performUserConfirmedReload(source: .userRequestedReload)
    }

    func confirmRecovery() {
        guard let prompt = recoveryPrompt else { return }
        recoveryPrompt = nil
        performUserConfirmedReload(source: prompt.trigger)
    }

    func dismissRecoveryPrompt() {
        recoveryPrompt = nil
    }

    private func promptRecovery(for trigger: RecoveryTrigger) {
        guard recoveryPrompt == nil else { return }
        let decision = recovery.decide(
            trigger: trigger,
            isPiPActive: session.pipVisible,
            hasLoadedPage: browser.hasLoadedPage
        )
        switch decision.action {
        case .promptUser(let reason):
            recoveryPrompt = RecoveryPrompt(
                trigger: trigger,
                title: "需要恢复页面",
                message: decision.userMessage ?? reason,
                confirmTitle: "重新加载"
            )
            diagnostics.warning(
                .recovery,
                "recovery.prompt",
                "需要用户确认后恢复",
                ["trigger": trigger.rawValue, "reason": reason]
            )
        case .noAction(let reason):
            diagnostics.info(
                .recovery,
                "recovery.no_action",
                reason,
                ["trigger": trigger.rawValue]
            )
            if let message = decision.userMessage {
                showToast(message, .warning)
            }
        case .reloadNow:
            // Non-user triggers must never reach this branch: that would be an automatic
            // reload, which this app deliberately does not implement.
            diagnostics.warning(.recovery, "recovery.unexpected_auto", "忽略自动重载分支")
        }
    }

    private func performUserConfirmedReload(source: RecoveryTrigger) {
        let decision = recovery.decide(
            trigger: .userRequestedReload,
            isPiPActive: session.pipVisible,
            hasLoadedPage: browser.hasLoadedPage
        )
        switch decision.action {
        case .reloadNow:
            if session.pipVisible {
                if pipManager.isPiPActive(for: browser) {
                    pipManager.exitPiP(for: browser)
                }
            }
            recovery.noteReloadAttempt()
            session.recoveryStarted()
            browser.reload()
            diagnostics.info(
                .recovery,
                "recovery.reload",
                "用户确认后重新加载",
                ["source": source.rawValue]
            )
            showToast("正在重新加载；若云游戏会话重新启动，可能产生额外云游戏时长", .warning)
        case .promptUser(let reason):
            showToast(decision.userMessage ?? reason, .warning)
        case .noAction(let reason):
            showToast(decision.userMessage ?? reason, .warning)
        }
    }

    // MARK: - Privacy

    /// Only invoked after an explicit destructive confirmation in Settings.
    func clearWebsiteData() async -> Bool {
        guard !isClearingWebsiteData else { return false }
        isClearingWebsiteData = true
        websiteDataError = nil
        defer { isClearingWebsiteData = false }

        if pipManager.activePiPTabID != nil {
            pipManager.exitActivePiP()
        }
        browser.resetToBlank()
        session.userExited()
        hasStartedBrowser = false
        route = .home
        updateMediaScheduling()
        recovery.reset()
        audioSession.deactivate()

        let result = await cookieStore.clearAll()
        switch result {
        case .success:
            diagnostics.info(.privacy, "privacy.data_cleared", "用户确认并清除了网站数据")
            showToast("网站数据已清除，登录状态已按网站策略退出", .info)
            return true
        case .failure(let error):
            websiteDataError = error.localizedDescription
            diagnostics.error(.privacy, "privacy.clear_failed", error.localizedDescription)
            showToast("清除网站数据失败", .error)
            return false
        }
    }

    // MARK: - External links

    func confirmExternalOpen() {
        browser.confirmExternalOpen()
    }

    func cancelExternalOpen() {
        browser.cancelExternalOpen()
    }

    // MARK: - Toast

    func showToast(_ text: String, _ kind: ToastKind = .info) {
        let message = ToastMessage(text: text, kind: kind)
        toast = message
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard !Task.isCancelled else { return }
            if self?.toast?.id == message.id {
                self?.toast = nil
            }
        }
    }

    // MARK: - Teardown (tests)

    func shutdown() {
        toastTask?.cancel()
        toastTask = nil
        cancellables.removeAll()
        network.stop()
        audioSession.deactivate()
        browser.tearDown()
    }

    // MARK: - Wiring

    #if DEBUG
    /// Test/QA-only hook: load a local page through the real BrowserView/browser shell without
    /// touching the official service. Used by session-retention integration tests.
    func loadDebugLocalPage(_ url: URL) {
        var policy = browser.navigationPolicy
        policy.allowsLocalTestPages = true
        if let port = url.port {
            policy.localTestPorts = [port]
        }
        policy.allowedFileDirectory = LocalHTTPServer.testPagesDirectory()
        browser.applyDebugNavigationPolicy(policy)

        route = .game
        hasStartedBrowser = true
        updateMediaScheduling()
        browser.webView.load(URLRequest(url: url))
    }

    /// Loads the bundled offline video page through the real BrowserView/browser shell. This is
    /// a visual smoke test only; it never touches the official service.
    private func openDebugLocalPage() async {
        guard let directory = LocalHTTPServer.testPagesDirectory() else {
            diagnostics.error(.test, "debug.local_page", "TestPages 资源缺失")
            return
        }
        do {
            let server = LocalHTTPServer(rootDirectory: directory)
            let port = try await server.start()
            debugLocalGameServer = server

            var policy = browser.navigationPolicy
            policy.allowsLocalTestPages = true
            policy.localTestPorts = [Int(port)]
            policy.allowedFileDirectory = directory
            browser.applyDebugNavigationPolicy(policy)

            route = .game
            hasStartedBrowser = true
            updateMediaScheduling()
            diagnostics.info(
                .test,
                "debug.local_page",
                "加载本地测试页到浏览器视图",
                ["port": String(port)]
            )
            guard let url = URL(string: "http://127.0.0.1:\(port)/native-video.html") else {
                return
            }
            browser.webView.load(URLRequest(url: url))
        } catch {
            diagnostics.error(.test, "debug.local_page_failed", error.localizedDescription)
            showToast("本地测试页启动失败", .error)
        }
    }
    #endif

    private func start() {
        network.start()
        diagnostics.info(
            .app,
            "app.launch",
            "Ariuno 启动",
            [
                "version": appVersion,
                "os": UIDevice.current.systemVersion,
                "simulator": Self.isSimulator ? "1" : "0"
            ]
        )
        if media.probeScriptLoaded {
            diagnostics.info(.media, "media.probe_loaded", "MediaProbe.js 已加载")
        } else {
            diagnostics.error(.media, "media.probe_missing", media.lastProbeError ?? "探测脚本缺失")
        }
        diagnostics.info(
            .pip,
            "pip.platform",
            pip.platformSupportsPiP ? "系统支持画中画" : "系统不支持画中画（模拟器通常如此）"
        )
        diagnostics.info(.pip, "pip.m4_status", NativePictureInPictureCoordinator.status.displayText)
    }

    private func wire() {
        tabs.onSessionCreated = { [weak self] session in
            self?.configure(session)
        }
        tabs.onSessionEvent = { [weak self] session, event in
            guard let self else { return }
            guard session === self.browser else {
                // Log failures for background tabs without hijacking the active tab's state.
                if case .webContentProcessTerminated = event {
                    self.diagnostics.warning(
                        .recovery,
                        "webcontent.terminated.background_tab",
                        "后台标签页 WebContent 进程终止；其他标签不受影响"
                    )
                }
                return
            }
            self.handleBrowserEvent(event)
        }
        tabs.onMediaSnapshot = { [weak self] session, aggregate, snapshot in
            guard let self else { return }
            // PiP must stay bound to its source tab, even when another tab is selected.
            pipManager.handle(aggregate: aggregate, snapshot: snapshot, from: session)
            guard session === self.browser else { return }
            self.handleMediaSnapshot(aggregate, snapshot: snapshot)
        }
        tabs.onMediaEvent = { [weak self] session, event in
            guard let self else { return }
            if event.name == .enterpictureinpicture {
                self.diagnostics.info(
                    .pip,
                    "pip.source_bound",
                    "媒体进入 PiP，来源标签已绑定",
                    ["source": Self.shortTabID(session.id)]
                )
            }
            pipManager.handle(event: event, from: session)
            if event.name == .leavepictureinpicture {
                pipManager.clearActivePiP(for: session)
                if pipManager.pendingCloseTabIDs.contains(session.id) {
                    self.completeDeferredPiPClose(session)
                }
            }
            guard session === self.browser else { return }
            self.handleMediaEvent(event)
        }
        tabs.onProbeError = { [weak self] session, message in
            guard session === self?.browser else { return }
            self?.diagnostics.warning(.media, "media.probe_error", message)
        }
        tabs.pipProtection = { [weak self] session in
            guard let self else { return false }
            return pipManager.isPiPActive(for: session)
        }
        tabs.onAnyChange = { [weak self] in
            self?.objectWillChange.send()
        }
        library.history.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        bookmarks.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        tabs.recentlyClosed.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        pipManager.onAnyChange = { [weak self] in
            self?.objectWillChange.send()
        }
        session.onDiagnostic = { [weak self] severity, code, message, metadata in
            self?.diagnostics.record(
                category: .session,
                severity: severity,
                code: code,
                message: message,
                metadata: metadata
            )
        }
        session.onTransition = { [weak self] previous, next in
            self?.handleSessionTransition(from: previous, to: next)
        }
        network.onChange = { [weak self] status in
            self?.handleNetworkChange(status)
        }
        audioSession.onError = { [weak self] message in
            self?.diagnostics.warning(.session, "audio.session_error", message)
        }

        settings.$enableInPagePiPButton
            .dropFirst()
            .sink { [weak self] enabled in
                self?.tabs.sessions.forEach { $0.mediaDetector.setInPageControlEnabled(enabled) }
                self?.diagnostics.info(
                    .app,
                    "settings.inpage_pip",
                    enabled ? "页面内 PiP 控件已启用" : "页面内 PiP 控件已禁用（子 frame 下次导航后生效）"
                )
            }
            .store(in: &cancellables)

        settings.$enableBackgroundAudio
            .dropFirst()
            .sink { [weak self] _ in
                self?.updateAudioSession()
            }
            .store(in: &cancellables)

        settings.$searchEngine
            .dropFirst()
            .sink { [weak self] engine in
                self?.diagnostics.info(.app, "settings.search_engine", engine.displayName)
            }
            .store(in: &cancellables)

        settings.$allowLocalTestPages
            .dropFirst()
            .sink { [weak self] enabled in
                self?.tabs.sessions.forEach { $0.updateLocalTestAccess(enabled: enabled) }
            }
            .store(in: &cancellables)
    }

    private func configure(_ session: BrowserSession) {
        pipManager.coordinator(for: session)
    }

    private func handleBrowserEvent(_ event: BrowserEvent) {
        switch event {
        case .loadStarted:
            recoveryPrompt = nil
            session.startLoading()
            diagnostics.info(.navigation, "nav.start", "开始加载主框架")

        case .navigationCommitted(let host):
            session.navigationCommitted()
            diagnostics.debug(
                .navigation,
                "nav.commit",
                "主框架已收到内容",
                ["host": host ?? ""]
            )

        case .loadFinished(let host):
            session.loadFinished()
            updateMediaScheduling()
            media.refreshNow()
            pip.refreshAvailability()
            if let url = browser.currentURL, !browser.isPrivate {
                library.history.record(title: browser.pageTitle, url: url)
            }
            diagnostics.info(
                .navigation,
                "nav.finish",
                "页面加载完成",
                ["host": host ?? ""]
            )

        case .navigationFailed(let failure):
            session.navigationFailed(TLSErrorClassifier.userMessage(for: failure))
            diagnostics.record(
                category: .navigation,
                severity: .error,
                code: failure.isTLSError ? "nav.tls_failure" : "nav.failure",
                message: TLSErrorClassifier.userMessage(for: failure),
                metadata: [
                    "code": String(failure.code),
                    "host": failure.host ?? "",
                    "tls": failure.isTLSError ? "1" : "0",
                    "provisional": failure.isProvisional ? "1" : "0"
                ]
            )
            if route == .game && !failure.isCancelled {
                promptRecovery(for: .navigationFailure)
            }

        case .webContentProcessTerminated:
            session.webContentTerminated()
            diagnostics.error(.recovery, "webcontent.terminated", "WebContent 进程终止")
            promptRecovery(for: .webContentTerminated)

        case .tlsChallenge(let host):
            diagnostics.debug(
                .security,
                "tls.challenge",
                "收到服务器信任校验；使用系统默认校验，不绕过证书错误",
                ["host": host]
            )

        case .redirect(let host):
            diagnostics.debug(.navigation, "nav.redirect", "服务器重定向", ["host": host ?? ""])

        case .blockedNavigation(let host, let reason):
            diagnostics.warning(
                .security,
                "nav.blocked",
                "已阻止导航",
                ["host": host ?? "", "reason": reason.rawValue]
            )

        case .externalURLRequested(let host):
            diagnostics.info(
                .navigation,
                "nav.external",
                "外部链接等待用户确认",
                ["host": host ?? ""]
            )

        case .externalOpenFailed:
            diagnostics.warning(.navigation, "nav.external_failed", "系统未能打开外部链接")
            showToast("系统未能打开该外部链接", .warning)

        case .httpError(let status, let host):
            diagnostics.warning(
                .navigation,
                "nav.http_error",
                "页面返回 HTTP \(status)",
                ["host": host ?? "", "status": String(status)]
            )

        case .mediaCaptureDenied(let host):
            diagnostics.warning(
                .security,
                "security.media_capture_denied",
                "已拒绝网页的摄像头/麦克风权限请求",
                ["host": host ?? ""]
            )

        case .downloadStarted(let filename):
            diagnostics.info(.download, "download.started", "开始下载文件", ["filename": filename])

        case .titleChanged:
            break
        }
        updateAudioSession()
    }

    private func handleMediaSnapshot(_ aggregate: MediaAggregate, snapshot: MediaFrameSnapshot) {
        session.handle(mediaAggregate: aggregate, snapshotReceivedAt: snapshot.receivedAt)
        pip.refreshAvailability()
        updateAudioSession()

        let signature = [
            aggregate.kind.rawValue,
            String(aggregate.videoCount),
            String(aggregate.playingVideoCount),
            String(aggregate.piPCapablePlayingVideoCount),
            aggregate.isInPiP ? "pip" : "inline"
        ].joined(separator: "|")

        if signature != lastSnapshotSignature {
            lastSnapshotSignature = signature
            diagnostics.info(
                .media,
                "media.snapshot",
                aggregate.summaryText,
                media.diagnosticsMetadata
            )
        } else if settings.verboseDiagnostics {
            diagnostics.debug(
                .media,
                "media.snapshot",
                aggregate.summaryText,
                media.diagnosticsMetadata
            )
        }
    }

    private func handleMediaEvent(_ event: MediaPlaybackEvent) {
        session.handle(mediaEvent: event)
        if event.name == .leavepictureinpicture {
            pipManager.clearActivePiP(for: browser)
        }
        updateAudioSession()

        switch event.name {
        case .enterpictureinpicture:
            diagnostics.info(
                .pip,
                "pip.entered",
                "网页报告已进入画中画",
                ["origin": event.origin, "mode": event.presentationMode ?? ""]
            )
        case .leavepictureinpicture:
            diagnostics.info(
                .pip,
                "pip.left",
                "网页报告已退出画中画；服务器会话状态 UNVERIFIED",
                ["origin": event.origin]
            )
        case .error:
            diagnostics.warning(
                .media,
                "media.error",
                "视频元素报告错误",
                ["origin": event.origin, "readyState": String(event.readyState ?? -1)]
            )
        case .waiting, .stalled:
            if settings.verboseDiagnostics {
                diagnostics.debug(
                    .media,
                    "media.\(event.name.rawValue)",
                    "媒体等待/停滞",
                    ["origin": event.origin]
                )
            }
        case .playing, .pause, .emptied, .loadedmetadata, .loadeddata,
             .presentationmodechanged, .visibilitychange, .domchanged:
            if settings.verboseDiagnostics {
                diagnostics.debug(
                    .media,
                    "media.\(event.name.rawValue)",
                    "媒体事件",
                    [
                        "origin": event.origin,
                        "topFrame": event.isTopFrame ? "1" : "0",
                        "mode": event.presentationMode ?? ""
                    ]
                )
            }
        }
    }

    private func handlePiPState(_ state: WebPictureInPictureCoordinator.State) {
        switch state {
        case .active:
            session.pipBecameActive()
        case .available, .unavailable:
            if session.pipVisible {
                session.pipBecameInactive()
            }
        case .unknown, .starting:
            break
        }
        updateAudioSession()
    }

    private func logPiPOutcome(_ outcome: PiPRequestOutcome, availability: PiPAvailability) {
        switch outcome {
        case .success(let method):
            diagnostics.info(
                .pip,
                "pip.success",
                "画中画请求成功",
                ["method": method]
            )
        case .failure(let reason, let detail):
            diagnostics.record(
                category: .pip,
                severity: reason == .requiresUserGesture ? .info : .warning,
                code: "pip.failure",
                message: reason.userMessage,
                metadata: [
                    "reason": reason.rawValue,
                    "detail": detail ?? "",
                    "available": availability.isAvailable ? "1" : "0"
                ]
            )
        }
    }

    private func handleSessionTransition(from previous: GameSessionState, to next: GameSessionState) {
        switch next {
        case .streamStalled:
            showToast("画面停滞；App 不会自动重连，可手动重试", .warning)
        case .disconnected:
            showToast("连接中断；等待网络恢复，不会自动重载", .warning)
        case .ready:
            if previous == .reconnecting {
                diagnostics.info(.recovery, "recovery.ready", "恢复后页面就绪")
            }
        case .failed:
            if recoveryPrompt == nil, session.failureReason?.contains("WebContent") == true {
                promptRecovery(for: .webContentTerminated)
            }
        case .pipActive:
            diagnostics.info(.pip, "pip.state_active", "状态机已进入画中画状态")
        default:
            break
        }
        updateAudioSession()
    }

    private func handleNetworkChange(_ status: NetworkStatus) {
        let previous = lastNetworkStatus
        lastNetworkStatus = status
        session.setNetworkStatus(status)
        diagnostics.info(
            .network,
            "network.change",
            "网络状态：\(status.displayName)",
            ["interface": status.rawValue]
        )
        if status == .unavailable {
            showToast("网络不可用；不会无限重试", .warning)
        } else if status.isAvailable, previous == .unavailable, session.state == .disconnected {
            showToast("网络已恢复；如画面未恢复可手动重连", .info)
        }
    }

    private func updateAudioSession() {
        // Audio state is global: a PiP window may belong to a background tab, so it must not
        // be deactivated just because the selected tab changed. Background playback without
        // PiP is still never used as a keep-alive trick.
        let pipActive = pipManager.activePiPTabID != nil
        let activeTabMediaPlaying = session.mediaPlayingObserved && session.appIsForeground
        audioSession.update(
            isMediaPlaying: activeTabMediaPlaying || pipActive,
            isPiPActive: pipActive,
            enabled: settings.enableBackgroundAudio,
            appIsForeground: session.appIsForeground
        )
    }

    /// True while any tab owns the single system PiP window, independent of selection.
    var isAnyPiPActive: Bool {
        pipManager.activePiPTabID != nil
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    private static func shortTabID(_ id: UUID) -> String {
        String(id.uuidString.prefix(8))
    }

    private static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }
}
