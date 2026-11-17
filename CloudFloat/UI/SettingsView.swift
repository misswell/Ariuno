import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var diagnostics: DiagnosticsStore
    @State private var showClearConfirmation = false

    var body: some View {
        Form {
            Section {
                Toggle("进入网页时收起为悬浮球", isOn: $settings.collapseToolbarToBallOnOpen)
                Toggle("自动隐藏工具栏", isOn: $settings.autoHideToolbar)
                if settings.autoHideToolbar {
                    Picker("隐藏延迟", selection: $settings.toolbarAutoHideDelay) {
                        Text("2 秒").tag(2.0)
                        Text("4 秒").tag(4.0)
                        Text("6 秒").tag(6.0)
                        Text("8 秒").tag(8.0)
                        Text("10 秒").tag(10.0)
                    }
                }
            } header: {
                Text("游戏界面")
            } footer: {
                Text("工具栏位于底部。可随时点击“收起为悬浮球”，把工具栏缩成可拖动的小球；点击小球恢复。开启上面的选项后，进入网页时会自动收起。自动隐藏延迟为 \(Int(settings.toolbarAutoHideDelay)) 秒。")
            }

            Section {
                Toggle("显示网页内 PiP 按钮", isOn: $settings.enableInPagePiPButton)
            } header: {
                Text("画中画")
            } footer: {
                Text("WebKit 要求来自网页内容的真实点击才能进入 HTML5 PiP。启用后，正在播放且支持 PiP 的视频右上角会显示一个小按钮。关闭后，原生按钮可能只能提示“需要网页内点击”；已存在的子 frame 在下次导航后生效。")
            }

            Section {
                Toggle("后台音频（仅真实媒体）", isOn: $settings.enableBackgroundAudio)
            } header: {
                Text("音频")
            } footer: {
                Text("仅在检测到真实视频播放或画中画可见时配置 AVAudioSession .playback。Ariuno 不会播放静音音频，也不会用音频保活。后台模式的使用说明与审核风险见 docs/background-audio.md。")
            }

            Section {
                LabeledContent("WebKit Cookie 记录", value: "\(coordinator.cookieStore.cookieRecordCount)")
                LabeledContent("已记录站点数", value: "\(coordinator.cookieStore.domainRecordCount)")
                Button(role: .destructive) {
                    showClearConfirmation = true
                } label: {
                    HStack {
                        if coordinator.isClearingWebsiteData {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(coordinator.isClearingWebsiteData ? "正在清除…" : "清除网站数据…")
                    }
                }
                .disabled(coordinator.isClearingWebsiteData)
            } header: {
                Text("隐私与数据")
            } footer: {
                Text("只统计域名级 Cookie 网站记录，不读取 Cookie 名称、值或 HttpOnly 内容；该计数不能证明登录状态。清除网站数据会退出登录，并删除 Cookie、本地存储与缓存；诊断日志与设置不会删除。")
            }

            Section {
                Picker("搜索引擎", selection: $settings.searchEngine) {
                    ForEach(SearchEngine.allCases) { engine in
                        Text(engine.displayName).tag(engine)
                    }
                }
                Toggle("详细诊断日志", isOn: $settings.verboseDiagnostics)
                LabeledContent("当前事件数", value: "\(diagnostics.events.count) / \(diagnostics.capacity)")
                if let highest = diagnostics.highestSeverity {
                    LabeledContent("最高级别", value: highest.displayName)
                }
            } header: {
                Text("诊断")
            } footer: {
                Text("诊断只保存在内存中，导出前会脱敏 URL、Cookie、令牌、邮箱、手机号与长密钥；不会自动上传。")
            }

            Section {
                if FeatureFlags.localTestServerEnabled {
                    Toggle("主浏览器允许本地测试页", isOn: $settings.allowLocalTestPages)
                    NavigationLink {
                        TestPageLabView()
                    } label: {
                        Label("测试页实验室", systemImage: "testtube.2")
                    }
                } else {
                    Text("本地测试页仅在 Debug 构建中可用。")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("开发者")
            } footer: {
                Text("测试页服务器只绑定 127.0.0.1，仅用于验证 WKWebView 媒体探测与 PiP 行为，不承载官方游戏会话。")
            }

            Section {
                LabeledContent("版本", value: versionText)
                LabeledContent("最低 iOS", value: FeatureFlags.minimumIOSVersion)
                LabeledContent("原生媒体管线 (M4)", value: NativePictureInPictureCoordinator.status.displayText)
                Text(FeatureFlags.privacyStatement)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Ariuno 是非官方浏览器工具，不使用游戏官方 Logo，不冒充官方客户端。云游戏服务条款、品牌授权与 App Review 2.5.4 的最终合规责任需在上架前由发布方确认。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } header: {
                Text("关于")
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "清除所有网站数据？",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("清除并退出登录", role: .destructive) {
                Task {
                    _ = await coordinator.clearWebsiteData()
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这会删除 WKWebView 的 Cookie、本地存储、IndexedDB 与缓存，并退出当前会话与画中画。下次打开官方页面需要重新登录。此操作不可撤销。")
        }
    }

    private var versionText: String {
        let environment = ExportDiagnostics.environment()
        return "\(environment.appVersion) (\(environment.appBuild))"
    }
}
