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
                HStack {
                    Text("悬浮球大小")
                    Slider(value: $settings.floatingBallDiameter, in: 40...80, step: 4)
                    Text("\(Int(settings.floatingBallDiameter)) pt")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
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
                Text("工具栏位于底部。可随时点击“全屏”，把工具栏缩成可拖动的小球并让网页铺满屏幕；点击小球退出全屏。开启上面的选项后，进入网页时会自动收起。自动隐藏延迟为 \(Int(settings.toolbarAutoHideDelay)) 秒。")
            }

            Section {
                insetRow("上边距", value: $settings.fullscreenInsetTop)
                insetRow("下边距", value: $settings.fullscreenInsetBottom)
                insetRow("左边距", value: $settings.fullscreenInsetLeft)
                insetRow("右边距", value: $settings.fullscreenInsetRight)
                Button("重置为 0") {
                    settings.fullscreenInsetTop = 0
                    settings.fullscreenInsetBottom = 0
                    settings.fullscreenInsetLeft = 0
                    settings.fullscreenInsetRight = 0
                }
            } header: {
                Text("全屏安全边距")
            } footer: {
                Text("全屏时为网页内容保留的额外边距（0–80 pt）。圆角屏幕、刘海或动态岛可能遮住网页按钮；如果游戏按钮贴边不好点，可以给对应方向留出边距。0 表示铺满屏幕。")
            }

            Section {
                Toggle("显示网页内 PiP 按钮（可拖动）", isOn: $settings.enableInPagePiPButton)
            } header: {
                Text("画中画")
            } footer: {
                Text("WebKit 要求来自网页内容的真实点击才能进入 HTML5 PiP。PiP 入口只有网页内一个按钮：按住即可拖动到任意位置，位置按站点记住；轻点进入画中画。关闭此开关可完全隐藏它。")
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
                NavigationLink {
                    ShortcutSettingsView()
                        .environmentObject(coordinator)
                } label: {
                    Label("常用网站", systemImage: "square.grid.2x2")
                }
                NavigationLink {
                    PiPCapabilityView()
                        .environmentObject(coordinator)
                        .environmentObject(settings)
                } label: {
                    Label("画中画能力检测", systemImage: "pip")
                }
                NavigationLink {
                    DiagnosticsView()
                } label: {
                    Label("会话诊断", systemImage: "waveform.path.ecg")
                }
            } header: {
                Text("工具与诊断")
            } footer: {
                Text("能力检测用于排查 PiP 不可用的原因；会话诊断只保存在内存中，导出前会脱敏。两者都不再占用浏览器首页。")
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

    private func insetRow(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
                .frame(width: 56, alignment: .leading)
            Slider(value: value, in: 0...80, step: 4)
            Text("\(Int(value.wrappedValue)) pt")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
        }
    }
}
