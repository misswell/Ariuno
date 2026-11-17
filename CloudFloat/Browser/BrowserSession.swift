import Combine
import Foundation
import UIKit
import WebKit

struct BrowserNavigationFailure: Equatable {
    let code: Int
    let message: String
    let host: String?
    let isTLSError: Bool
    let isCancelled: Bool
    let isProvisional: Bool
}

enum BrowserEvent: Equatable {
    case loadStarted
    case navigationCommitted(host: String?)
    case loadFinished(host: String?)
    case navigationFailed(BrowserNavigationFailure)
    case webContentProcessTerminated
    case tlsChallenge(host: String)
    case redirect(host: String?)
    case blockedNavigation(host: String?, reason: NavigationBlockReason)
    case externalURLRequested(host: String?)
    case externalOpenFailed
    case httpError(status: Int, host: String?)
    case mediaCaptureDenied(host: String?)
    case downloadStarted(filename: String)
    case popupOpened
    case popupClosed
    case popupNavigationFailed(String)
    case titleChanged
}

struct ActivePopup: Identifiable {
    let id: UUID
    let webView: WKWebView

    init(webView: WKWebView) {
        self.id = UUID()
        self.webView = webView
    }
}

/// Long-lived browser session. The `WKWebView` is created exactly once and must be held by a
/// stable owner (AppCoordinator); SwiftUI view refreshes and PiP transitions must never
/// recreate it. It is never reloaded merely because the app backgrounds.
@MainActor
final class BrowserSession: NSObject, ObservableObject, Identifiable {
    let id: UUID
    let isPrivate: Bool
    let webView: WKWebView
    let configuration: WKWebViewConfiguration
    let mediaDetector: MediaDetector
    let cookieStore: CookieStore
    /// App-wide download queue. Injected so every tab reports into the same Downloads UI.
    let downloadManager: DownloadManager
    private(set) var navigationPolicy: NavigationPolicy

    /// New-window and close-window routing. BrowserTabManager installs these so target=_blank
    /// and window.open become real tabs, while window.close closes the source tab.
    var onCreateWindow: ((WKWebViewConfiguration, WKNavigationAction) -> WKWebView?)?
    var onCloseWindow: ((BrowserSession) -> Void)?
    /// Lets tab managers and coordinators mirror session changes upward.
    var onAnyChange: (() -> Void)?

    @Published private(set) var currentURL: URL?
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var isLoading = false
    @Published private(set) var estimatedProgress = 0.0
    @Published private(set) var hasOnlySecureContent = false
    @Published private(set) var hasCommittedPage = false
    @Published private(set) var currentHost: String?
    @Published private(set) var pageTitle: String = ""
    @Published private(set) var lastVisitedAt: Date
    @Published private(set) var isClosed = false
    @Published private(set) var lastNavigationFailure: BrowserNavigationFailure?
    @Published private(set) var webContentTerminatedCount = 0
    @Published private(set) var pendingExternalURL: URL?
    @Published private(set) var activePopup: ActivePopup?
    @Published private(set) var loadGeneration = 0

    var onEvent: ((BrowserEvent) -> Void)?

    private(set) var navigationDelegate: BrowserNavigationDelegate!
    private(set) var uiDelegate: BrowserUIDelegate!
    private var popupNavigationDelegate: PopupNavigationDelegate?
    private var popupUIDelegate: PopupUIDelegate?
    private var titleObservation: NSKeyValueObservation?
    private var urlObservation: NSKeyValueObservation?
    private var navigationObservation: NSKeyValueObservation?
    private var backForwardObservation: NSKeyValueObservation?
    private var progressObservation: NSKeyValueObservation?
    private var securityObservation: NSKeyValueObservation?
    private var objectWillChangeObservation: AnyCancellable?
    private let now: () -> Date
    /// Suppresses delegate-driven session events while the page is being torn down with
    /// about:blank (user exit) or during explicit teardown.
    private var suppressNavigationEvents = false
    private var hasRequestedInitialLoad = false
    private var sessionEnded = false
    /// Title/URL restored from cold-start persistence. The page itself is only loaded when the
    /// tab is first activated, so restoring 20 tabs does not start 20 network requests.
    private var restoredTitle = ""
    private var restoredURL: URL?
    private var pendingRestoredURL: URL?

    init(
        id: UUID = UUID(),
        navigationPolicy: NavigationPolicy = NavigationPolicy(),
        inPageControlEnabled: Bool = true,
        javaScriptCanOpenWindowsAutomatically: Bool = false,
        websiteDataStore: WKWebsiteDataStore = .default(),
        isPrivate: Bool = false,
        injectedConfiguration: WKWebViewConfiguration? = nil,
        downloadManager: DownloadManager? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.id = id
        self.downloadManager = downloadManager ?? DownloadManager()
        self.now = now
        self.lastVisitedAt = now()
        self.isPrivate = isPrivate || (injectedConfiguration?.websiteDataStore.isPersistent == false)
        let configuration = injectedConfiguration ?? WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        if injectedConfiguration == nil {
            configuration.websiteDataStore = websiteDataStore
        }
        configuration.mediaTypesRequiringUserActionForPlayback = .audio
        configuration.preferences.isElementFullscreenEnabled = true
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        // Default false: script-initiated popups require a user gesture. Tests may opt in to
        // exercise the popup plumbing; production never enables automatic windows.
        configuration.preferences.javaScriptCanOpenWindowsAutomatically =
            javaScriptCanOpenWindowsAutomatically
        self.configuration = configuration

        self.mediaDetector = MediaDetector(
            configuration: configuration,
            inPageControlEnabled: inPageControlEnabled,
            now: now
        )
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        self.cookieStore = CookieStore(dataStore: configuration.websiteDataStore, now: now)
        self.navigationPolicy = navigationPolicy

        super.init()

        self.navigationDelegate = BrowserNavigationDelegate(session: self)
        self.uiDelegate = BrowserUIDelegate(session: self)
        webView.navigationDelegate = navigationDelegate
        webView.uiDelegate = uiDelegate
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.backgroundColor = .black
        webView.isOpaque = true
        // Keep the system mobile User-Agent. Do not spoof a desktop browser or bypass any
        // device checks performed by the official page.
        webView.customUserAgent = nil
        #if DEBUG
        webView.isInspectable = true
        #endif

        mediaDetector.attach(webView: webView)
        cookieStore.start()
        observeWebView()
        objectWillChangeObservation = objectWillChange.sink { [weak self] _ in
            self?.onAnyChange?()
        }
    }

    var pictureInPictureAllowedByConfiguration: Bool {
        configuration.allowsPictureInPictureMediaPlayback
    }

    /// Developer test-page access is a runtime switch, but only ever enabled in DEBUG builds.
    func updateLocalTestAccess(enabled: Bool) {
        var policy = navigationPolicy
        policy.allowsLocalTestPages = enabled && FeatureFlags.localTestServerEnabled
        navigationPolicy = policy
    }

    #if DEBUG
    /// Debug-only hook used by the local-game smoke-test launch argument. Never available in
    /// Release builds.
    func applyDebugNavigationPolicy(_ policy: NavigationPolicy) {
        guard FeatureFlags.localTestServerEnabled else { return }
        navigationPolicy = policy
    }
    #endif

    var hasLoadedPage: Bool {
        hasCommittedPage
    }

    /// Title to show in tab UI: live page title first, restored metadata second.
    var displayTitle: String {
        let live = pageTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !live.isEmpty { return live }
        let restored = restoredTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !restored.isEmpty { return restored }
        return restoredURL?.host ?? ""
    }

    /// Metadata shown while a restored tab has not been loaded yet.
    var displayURL: URL? {
        currentURL ?? restoredURL
    }

    /// Applies cold-start metadata without touching the network. `resumeRestoredPageIfNeeded()`
    /// performs the actual load when the user first activates the tab.
    func applyRestoredMetadata(url: URL, title: String, lastVisitedAt: Date) {
        restoredURL = url
        pendingRestoredURL = url
        restoredTitle = title
        self.lastVisitedAt = lastVisitedAt
        currentURL = url
        currentHost = url.host
    }

    /// Loads the persisted URL exactly once. Cold-start restoration is allowed to reload the
    /// page; ordinary tab switches never do.
    @discardableResult
    func resumeRestoredPageIfNeeded() -> Bool {
        guard let url = pendingRestoredURL, isShowingBlankPage else { return false }
        pendingRestoredURL = nil
        loadURL(url)
        return true
    }

    var pendingExternalHost: String {
        guard let url = pendingExternalURL else { return "" }
        return url.host ?? (url.scheme ?? "外部链接")
    }

    var isShowingBlankPage: Bool {
        sessionEnded || webView.url == nil || webView.url?.absoluteString == "about:blank"
    }

    // MARK: - Navigation

    /// Loads an arbitrary URL. NavigationPolicy still gates the navigation; no URL is
    /// hard-coded into the browser session.
    func loadURL(_ url: URL) {
        sessionEnded = false
        suppressNavigationEvents = false
        hasRequestedInitialLoad = true
        restoredURL = nil
        pendingRestoredURL = nil
        restoredTitle = ""
        webView.stopLoading()
        closePopup()
        pendingExternalURL = nil
        lastNavigationFailure = nil
        loadGeneration += 1
        mediaDetector.clearFrames(reason: "user-navigation")
        webView.load(URLRequest(
            url: url,
            cachePolicy: .useProtocolCachePolicy,
            timeoutInterval: 60
        ))
    }

    func reload() {
        guard let url = webView.url else { return }
        sessionEnded = false
        suppressNavigationEvents = false
        hasRequestedInitialLoad = true
        closePopup()
        pendingExternalURL = nil
        lastNavigationFailure = nil
        loadGeneration += 1
        mediaDetector.clearFrames(reason: "user-reload")
        webView.reload()
        _ = url
    }

    func stop() {
        webView.stopLoading()
    }

    @discardableResult
    func goBack() -> Bool {
        guard canGoBack else { return false }
        suppressNavigationEvents = false
        return webView.goBack() != nil
    }

    @discardableResult
    func goForward() -> Bool {
        guard canGoForward else { return false }
        suppressNavigationEvents = false
        return webView.goForward() != nil
    }

    /// Keeps the API surface browser-like while preserving WebKit website data.
    func resetToBlank() {
        suppressNavigationEvents = true
        sessionEnded = true
        hasRequestedInitialLoad = false
        webView.stopLoading()
        closePopup()
        pendingExternalURL = nil
        lastNavigationFailure = nil
        hasCommittedPage = false
        isLoading = false
        currentURL = nil
        currentHost = nil
        pageTitle = ""
        loadGeneration += 1
        mediaDetector.clearFrames(reason: "user-exit")
        mediaDetector.stopPolling()
        webView.load(URLRequest(url: URL(string: "about:blank")!))
    }

    /// Called on foreground only to refresh observations. It never reloads.
    func verifyExistingPageOnForeground() {
        guard !isShowingBlankPage else { return }
        mediaDetector.refreshNow()
    }

    // MARK: - Delegate callbacks

    func handleNavigationStarted() {
        guard !suppressNavigationEvents else { return }
        isLoading = true
        hasCommittedPage = false
        lastNavigationFailure = nil
        mediaDetector.clearFrames(reason: "navigation-started")
        onEvent?(.loadStarted)
    }

    func handleNavigationCommitted() {
        guard !suppressNavigationEvents else { return }
        hasCommittedPage = true
        isLoading = true
        currentHost = webView.url?.host
        onEvent?(.navigationCommitted(host: currentHost))
    }

    func handleNavigationFinished() {
        guard !suppressNavigationEvents else { return }
        isLoading = false
        hasCommittedPage = true
        lastNavigationFailure = nil
        lastVisitedAt = now()
        currentHost = webView.url?.host
        mediaDetector.refreshNow()
        onEvent?(.loadFinished(host: currentHost))
    }

    func handleNavigationFailure(error: Error, isProvisional: Bool) {
        guard !suppressNavigationEvents else { return }
        let nsError = error as NSError
        let failure = BrowserNavigationFailure(
            code: nsError.code,
            message: PrivacyRedactor.redact(nsError.localizedDescription),
            host: webView.url?.host,
            isTLSError: TLSErrorClassifier.isTLSFailure(domain: nsError.domain, code: nsError.code),
            isCancelled: nsError.code == NSURLErrorCancelled,
            isProvisional: isProvisional
        )
        isLoading = false
        guard !failure.isCancelled else { return }
        lastNavigationFailure = failure
        hasCommittedPage = false
        onEvent?(.navigationFailed(failure))
    }

    func handleWebContentProcessTermination() {
        guard !suppressNavigationEvents else { return }
        webContentTerminatedCount += 1
        isLoading = false
        hasCommittedPage = false
        mediaDetector.clearFrames(reason: "webcontent-terminated")
        hasRequestedInitialLoad = true
        sessionEnded = false
        onEvent?(.webContentProcessTerminated)
    }

    func recordTLSChallenge(host: String) {
        onEvent?(.tlsChallenge(host: host))
    }

    func recordRedirect(host: String?) {
        onEvent?(.redirect(host: host))
    }

    func recordBlockedNavigation(url: URL?, reason: NavigationBlockReason) {
        onEvent?(.blockedNavigation(host: url?.host, reason: reason))
    }

    func recordHTTPError(status: Int, host: String?) {
        onEvent?(.httpError(status: status, host: host))
    }

    func recordMediaCaptureDenied(host: String?) {
        onEvent?(.mediaCaptureDenied(host: host))
    }

    func recordDownloadStarted(response: URLResponse) {
        onEvent?(.downloadStarted(filename: response.suggestedFilename ?? "download"))
    }

    func registerDownload(_ download: WKDownload) {
        downloadManager.register(download: download)
    }

    func recordPopupNavigationFailure(error: Error) {
        onEvent?(.popupNavigationFailed(PrivacyRedactor.redact(error.localizedDescription)))
    }

    func handlePopupProcessTermination() {
        onEvent?(.popupNavigationFailed("登录窗口的 WebContent 进程已终止"))
        closePopup()
    }

    // MARK: - External links

    /// External schemes are never executed inside WebKit. http(s)/mailto/tel are queued for
    /// an explicit user confirmation, then opened by the system.
    func requestExternalOpen(_ url: URL) {
        guard let scheme = url.scheme?.lowercased(),
              ["https", "http", "mailto", "tel", "sms", "facetime", "facetime-audio"].contains(scheme) else {
            recordBlockedNavigation(url: url, reason: .unsafeScheme)
            return
        }
        pendingExternalURL = url
        onEvent?(.externalURLRequested(host: url.host))
    }

    func confirmExternalOpen() {
        guard let url = pendingExternalURL else { return }
        pendingExternalURL = nil
        UIApplication.shared.open(url, options: [:]) { [weak self] success in
            guard !success else { return }
            Task { @MainActor in
                self?.onEvent?(.externalOpenFailed)
            }
        }
    }

    func cancelExternalOpen() {
        pendingExternalURL = nil
    }

    // MARK: - New windows / tabs

    /// Called by BrowserUIDelegate for target=_blank and window.open. BrowserTabManager
    /// supplies the handler and owns the resulting tab.
    /// Compatibility no-op: target=_blank/window.open are routed to BrowserTabManager.
    func closePopup() {}

    func handleCreateWindow(
        configuration: WKWebViewConfiguration,
        navigationAction: WKNavigationAction
    ) -> WKWebView? {
        onCreateWindow?(configuration, navigationAction)
    }

    func requestClose() {
        onCloseWindow?(self)
    }

    // MARK: - Teardown (tests / explicit exit)

    func tearDown() {
        guard !isClosed else { return }
        isClosed = true
        cookieStore.stop()
        mediaDetector.shutdown()
        closePopup()
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        titleObservation = nil
        urlObservation = nil
        navigationObservation = nil
        backForwardObservation = nil
        progressObservation = nil
        securityObservation = nil
        objectWillChangeObservation = nil
        onEvent = nil
        onCreateWindow = nil
        onCloseWindow = nil
        onAnyChange = nil
    }

    // MARK: - KVO

    private func observeWebView() {
        titleObservation = webView.observe(\.title, options: [.new]) { [weak self] webView, _ in
            let title = webView.title ?? ""
            Task { @MainActor in
                guard let self else { return }
                self.pageTitle = String(title.prefix(120))
                self.onEvent?(.titleChanged)
            }
        }
        urlObservation = webView.observe(\.url, options: [.new]) { [weak self] webView, _ in
            let url = webView.url
            let host = url?.host
            Task { @MainActor in
                guard let self else { return }
                self.currentURL = url
                self.currentHost = host
            }
        }
        navigationObservation = webView.observe(\.canGoBack, options: [.new]) { [weak self] webView, _ in
            let value = webView.canGoBack
            Task { @MainActor in
                self?.canGoBack = value
            }
        }
        backForwardObservation = webView.observe(\.canGoForward, options: [.new]) { [weak self] webView, _ in
            let value = webView.canGoForward
            Task { @MainActor in
                self?.canGoForward = value
            }
        }
        progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
            let value = webView.estimatedProgress
            Task { @MainActor in
                self?.estimatedProgress = value
            }
        }
        securityObservation = webView.observe(\.hasOnlySecureContent, options: [.new]) { [weak self] webView, _ in
            let value = webView.hasOnlySecureContent
            Task { @MainActor in
                self?.hasOnlySecureContent = value
            }
        }
    }
}

enum TLSErrorClassifier {
    static let tlsErrorCodes: Set<Int> = [
        NSURLErrorSecureConnectionFailed,
        NSURLErrorServerCertificateHasBadDate,
        NSURLErrorServerCertificateUntrusted,
        NSURLErrorServerCertificateHasUnknownRoot,
        NSURLErrorServerCertificateNotYetValid,
        NSURLErrorClientCertificateRejected,
        NSURLErrorClientCertificateRequired,
        NSURLErrorAppTransportSecurityRequiresSecureConnection
    ]

    static func isTLSFailure(domain: String, code: Int) -> Bool {
        domain == NSURLErrorDomain && tlsErrorCodes.contains(code)
    }

    static func userMessage(for failure: BrowserNavigationFailure) -> String {
        if failure.isTLSError {
            return "TLS/证书校验失败。App 使用系统默认校验并已拒绝连接，不会忽略证书错误。"
        }
        switch failure.code {
        case NSURLErrorNotConnectedToInternet:
            return "设备当前没有网络连接。"
        case NSURLErrorTimedOut:
            return "页面加载超时。"
        case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost, NSURLErrorDNSLookupFailed:
            return "无法连接官方服务器。"
        case NSURLErrorNetworkConnectionLost:
            return "网络连接已断开。"
        case NSURLErrorCancelled:
            return "加载已取消。"
        default:
            return "页面加载失败（错误码 \(failure.code)）。"
        }
    }
}
