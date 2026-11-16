import AVKit
import SwiftUI
import WebKit

enum TestLabPage: String, CaseIterable, Identifiable {
    case nativeVideo
    case canvasOnly
    case nestedIframe
    case loginPopup

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nativeVideo: return "原生视频"
        case .canvasOnly: return "仅 Canvas"
        case .nestedIframe: return "跨域 iframe"
        case .loginPopup: return "登录弹窗"
        }
    }

    var filename: String {
        switch self {
        case .nativeVideo: return "native-video.html"
        case .canvasOnly: return "canvas-only.html"
        case .nestedIframe: return "nested-iframe.html"
        case .loginPopup: return "login-popup.html"
        }
    }
}

@MainActor
final class TestPageLabModel: ObservableObject {
    @Published var page: TestLabPage = .nativeVideo {
        didSet {
            guard oldValue != page else { return }
            loadSelectedPage()
        }
    }
    @Published var showInPageControl: Bool = true {
        didSet {
            detector.setInPageControlEnabled(showInPageControl)
        }
    }
    @Published private(set) var serverStatus = "未启动"
    @Published private(set) var isRunning = false
    @Published private(set) var aggregate: MediaAggregate = .empty
    @Published private(set) var lastEventDescription = "—"
    @Published private(set) var lastSnapshotAt: Date?
    @Published private(set) var lastPiPResult: String?
    @Published var errorMessage: String?

    let webView: WKWebView
    let detector: MediaDetector

    private var primaryServer: LocalHTTPServer?
    private var secondaryServer: LocalHTTPServer?
    private var urls: [TestLabPage: URL] = [:]
    private var started = false

    var platformSupportsPiP: Bool {
        AVPictureInPictureController.isPictureInPictureSupported()
    }

    init() {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        // Keep test pages completely separate from the game's persistent login data.
        configuration.websiteDataStore = .nonPersistent()
        configuration.mediaTypesRequiringUserActionForPlayback = .audio
        configuration.preferences.isElementFullscreenEnabled = true
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let detector = MediaDetector(configuration: configuration, inPageControlEnabled: true)
        self.detector = detector
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.backgroundColor = .black
        webView.isOpaque = true
        #if DEBUG
        webView.isInspectable = true
        #endif
        detector.attach(webView: webView)
        detector.onSnapshot = { [weak self] aggregate, _ in
            self?.aggregate = aggregate
            self?.lastSnapshotAt = Date()
        }
        detector.onEvent = { [weak self] event in
            self?.lastEventDescription = [
                event.name.rawValue,
                event.origin,
                event.videoIndex.map { "#\($0)" } ?? ""
            ].filter { !$0.isEmpty }.joined(separator: " · ")
        }
        detector.onProbeError = { [weak self] message in
            self?.errorMessage = message
        }
    }

    func start() async {
        guard !started else {
            loadSelectedPage()
            return
        }
        guard let directory = LocalHTTPServer.testPagesDirectory() else {
            errorMessage = LocalHTTPServer.ServerError.testPagesMissing.localizedDescription
            serverStatus = "缺少测试页资源"
            return
        }
        do {
            let primary = LocalHTTPServer(rootDirectory: directory)
            let primaryPort = try await primary.start()
            let secondary = LocalHTTPServer(rootDirectory: directory)
            let secondaryPort = try await secondary.start()
            primaryServer = primary
            secondaryServer = secondary

            guard let primaryBase = URL(string: "http://127.0.0.1:\(primaryPort)/"),
                  let secondaryBase = URL(string: "http://127.0.0.1:\(secondaryPort)/") else {
                throw LocalHTTPServer.ServerError.failedToStart("无效端口")
            }

            urls[.nativeVideo] = primaryBase.appendingPathComponent(TestLabPage.nativeVideo.filename)
            urls[.canvasOnly] = primaryBase.appendingPathComponent(TestLabPage.canvasOnly.filename)
            var components = URLComponents(
                url: primaryBase.appendingPathComponent(TestLabPage.nestedIframe.filename),
                resolvingAgainstBaseURL: false
            )
            let childURL = secondaryBase.appendingPathComponent(TestLabPage.nativeVideo.filename)
            components?.queryItems = [URLQueryItem(name: "child", value: childURL.absoluteString)]
            urls[.nestedIframe] = components?.url
            urls[.loginPopup] = primaryBase.appendingPathComponent(TestLabPage.loginPopup.filename)

            started = true
            isRunning = true
            serverStatus = "运行中 · 主 \(primaryPort) / 子 \(secondaryPort)"
            detector.startPolling()
            loadSelectedPage()
        } catch {
            errorMessage = error.localizedDescription
            serverStatus = "启动失败"
            stop()
        }
    }

    func stop() {
        detector.stopPolling()
        detector.shutdown()
        primaryServer?.stop()
        secondaryServer?.stop()
        primaryServer = nil
        secondaryServer = nil
        webView.stopLoading()
        started = false
        isRunning = false
    }

    func reload() {
        detector.clearFrames(reason: "lab-reload")
        webView.reload()
    }

    func loadSelectedPage() {
        guard let url = urls[page] else { return }
        detector.clearFrames(reason: "lab-page-change")
        webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
    }

    func showInPagePiPControl() {
        _ = detector.showInPagePiPControl()
    }

    func requestPiP() async {
        let outcome = await detector.requestPiP()
        switch outcome {
        case .success(let method):
            lastPiPResult = "成功：\(method)"
        case .failure(let reason, let detail):
            lastPiPResult = "失败：\(reason.userMessage)\(detail.map { "（\($0)）" } ?? "")"
        }
    }
}

struct TestPageLabView: View {
    @StateObject private var lab = TestPageLabModel()

    var body: some View {
        List {
            Section {
                ZStack {
                    Color.black
                    CloudWebView(webView: lab.webView)
                }
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .listRowInsets(EdgeInsets())
            }

            Section("测试页面") {
                Picker("页面", selection: $lab.page) {
                    ForEach(TestLabPage.allCases) { page in
                        Text(page.title).tag(page)
                    }
                }
                .pickerStyle(.segmented)
                LabeledContent("服务器", value: lab.serverStatus)
                LabeledContent("系统 PiP", value: lab.platformSupportsPiP ? "支持" : "不支持（模拟器常见）")
            }

            Section("媒体探测") {
                LabeledContent("媒体类型", value: lab.aggregate.kind.displayName)
                LabeledContent("视频", value: "\(lab.aggregate.videoCount) 个 / 播放中 \(lab.aggregate.playingVideoCount) 个")
                LabeledContent("可 PiP 播放中", value: "\(lab.aggregate.piPCapablePlayingVideoCount) 个")
                LabeledContent("Canvas / iframe", value: "\(lab.aggregate.canvasCount) / \(lab.aggregate.iframeCount)")
                LabeledContent("frame", value: "\(lab.aggregate.frameCount) 个")
                LabeledContent("站点", value: lab.aggregate.origins.isEmpty ? "—" : lab.aggregate.origins.joined(separator: ", "))
                LabeledContent("最近事件", value: lab.lastEventDescription)
                if let at = lab.lastSnapshotAt {
                    LabeledContent("最近快照", value: Self.timeFormatter.string(from: at))
                }
                if let result = lab.lastPiPResult {
                    LabeledContent("最近 PiP 结果", value: result)
                }
            }

            Section("操作") {
                Button {
                    lab.reload()
                } label: {
                    Label("重新加载页面", systemImage: "arrow.clockwise")
                }
                Button {
                    lab.showInPagePiPControl()
                } label: {
                    Label("显示网页内 PiP 按钮", systemImage: "pip")
                }
                Button {
                    Task { @MainActor in
                        await lab.requestPiP()
                    }
                } label: {
                    Label("尝试原生触发 PiP", systemImage: "pip.fill")
                }
                Toggle("网页内 PiP 控件", isOn: $lab.showInPageControl)
            }

            Section {
                Text("测试页服务器只绑定 127.0.0.1，并使用 nonPersistent 网站数据，不会影响游戏登录。跨域 iframe 页面由两个不同端口的回环服务器提供，因此父子 frame 确实是不同源。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("系统画中画通常只在真实 iPhone 上可用。模拟器可以验证 DOM 探测、Canvas/iframe 分类与错误映射，但不能证明 PiP 成功。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("“尝试原生触发 PiP”走 evaluateJavaScript，通常缺少 WebKit 要求的用户激活，预期会失败并提示使用网页内按钮；该失败路径本身也是需要验证的行为。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("说明")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("测试页实验室")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await lab.start()
        }
        .onDisappear {
            lab.stop()
        }
        .alert(
            "测试页实验室",
            isPresented: Binding(
                get: { lab.errorMessage != nil },
                set: { if !$0 { lab.errorMessage = nil } }
            )
        ) {
            Button("好", role: .cancel) { lab.errorMessage = nil }
        } message: {
            Text(lab.errorMessage ?? "")
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
