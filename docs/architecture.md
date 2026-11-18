# Ariuno 架构说明

- 平台：iOS 17.0+，Swift 5 语言模式，SwiftUI + WebKit + AVKit/AVFoundation。
- 目标：在官方网页内完成登录/游玩，通过网页 HTML5 PiP 提供系统浮窗，并如实观测/诊断“PiP、媒体实时性、服务器会话”三层状态。
- 非目标：自动战斗、自动点击、伪后台、私有 API、绕过登录/反作弊/DRM、保证服务器会话持续。

## 1. 总览

```text
AriunoApp (@main)
└── RootView
    ├── BrowserStartPageView / SettingsView / DiagnosticsView / PiPCapabilityView
    └── BrowserView（启动后常驻，切换标签不销毁）
        └── CloudWebView → BrowserSession.webView (single WKWebView)

AppCoordinator (@MainActor, composition root)
├── AppSettings (UserDefaults, non-sensitive)
├── DiagnosticsStore (in-memory, bounded, redacted)
├── BrowserTabManager（标签唯一事实来源）
│   ├── BrowserSession × N
│   │   ├── WKWebView + WKWebViewConfiguration
│   │   ├── BrowserNavigationDelegate / BrowserUIDelegate
│   │   ├── CookieStore (counts only)
│   │   ├── MediaDetector (JS bridge)
│   │   └── DownloadManager
│   ├── TabSessionStore（版本化 tabs-v1.json）
│   └── RecentlyClosedStore
├── PiPManager（全局 PiP 来源 + 控制器表 + 待关闭集合）
├── TabThumbnailCache（Caches/Ariuno/TabThumbnails）
├── BrowserLibraryStore（BookmarkStore + HistoryStore）
├── SessionMonitor (SessionStateMachine, timers, lifecycle/network)
├── WebContentRecovery (RecoveryPolicy)
├── NetworkObserver (NWPathMonitor)
└── AudioSessionManager (AVAudioSession, real media only)
```

所有 UI/浏览器/状态对象都在主线程（`@MainActor`）上创建和变更；WebKit 的 delegate 回调也在主线程。后台不依赖 JS 定时器，不把 JS 心跳当作服务器会话证明。

## 2. 浏览器内核（M1）

### 2.1 多实例 WebView

每个标签页由 [`BrowserSession`](../CloudFloat/Browser/BrowserSession.swift) 持有一个独立 `WKWebView`；[`BrowserTabManager`](../CloudFloat/Browser/BrowserTabManager.swift) 负责创建、切换、关闭和转发事件：

- `allowsInlineMediaPlayback = true`
- `allowsPictureInPictureMediaPlayback = true`
- 普通标签共享 `.default()` 网站数据存储（Cookie/本地存储）；
- 隐私标签共享同一个 `.nonPersistent()` 网站数据存储，且不进入历史/最近关闭；
- `mediaTypesRequiringUserActionForPlayback = .audio`（保留正常用户播放语义）
- `preferences.isElementFullscreenEnabled = true`
- `defaultWebpagePreferences.allowsContentJavaScript = true`
- `webView.customUserAgent = nil`（保留系统移动 UA，不伪造桌面浏览器）
- `estimatedProgress`、`hasOnlySecureContent`、`canGoBack/canGoForward`、`currentURL` 均 KVO 观察并发布；
- `#if DEBUG webView.isInspectable = true`
- `javaScriptCanOpenWindowsAutomatically = false`（生产默认；避免无手势脚本弹窗）

`RootView` 在 `hasStartedBrowser` 之后始终保留 `BrowserView`（返回首页时用 `opacity(0)` 隐藏但仍在视图层级），
`CloudWebView.makeUIView` 返回同一个 `WKWebView`，`BrowserSession` 由 `@StateObject AppCoordinator` 长期持有。

[`BrowserTabHostView`](../CloudFloat/Browser/CloudWebView.swift) 将**所有标签**的 WebView 常驻挂载，
仅活动标签 `opacity(1)` + 可交互，其他标签 `opacity(0)` 但保持视图层级。切换标签只改变可见性：
不重建 WebView、不 reload、不改变 `loadGeneration`。`BrowserContainerTests` 验证 10 个标签切换后
对象标识不变且从未发起导航。取舍：以常驻内存换取页面状态（JS、滚动、历史栈、媒体）绝对不丢失；
关闭标签时 `tearDown()` 停止轮询、移除 message handler、取消 KVO/Combine、置 `isClosed`。

### 2.1.1 标签冷启动持久化

[`TabSessionStore`](../CloudFloat/Browser/TabSessionStore.swift) 将普通标签的 URL/标题/最后访问时间/
活动标签写入 `Application Support/Ariuno/tabs-v1.json`：

- `version` 不匹配直接丢弃（不猜测结构）；
- 过滤 `about:blank`/空 URL，按 tabID 去重，上限 20；
- 0.4 秒防抖 + `Data.write(options: .atomic)`；进入后台 `flush()`；
- 隐私标签永不写入；
- 冷启动只恢复元数据（`BrowserSession.applyRestoredMetadata`），用户首次激活时
  `resumeRestoredPageIfNeeded()` 才发起一次导航，避免启动时同时请求全部标签。

### 2.2 导航与外部 URL

[`NavigationPolicy`](../CloudFloat/Browser/NavigationPolicy.swift) 是纯 Foundation 的通用浏览器策略，
**不再包含任何游戏官方域名白名单**：

- 任意 `http`/`https` 均在站内打开；`http` 由地址栏明确标注“不安全”；
- 表单提交、重定向、子 frame、当前标签前进/后退 → 允许；
- `file` 只允许 Debug 测试页目录；`javascript/data/blob/filesystem` 阻止；
- `itms-services/itms-apps` 阻止；`mailto/tel/sms/facetime` 经用户确认交给系统；
- 未知自定义 scheme 阻止；
- TLS 继续使用系统默认校验，`shouldAllowDeprecatedTLS = false`，不忽略证书错误；
- ATS 只在 `NSAllowsArbitraryLoadsInWebContent` 范围内允许网页内容加载 HTTP，
  不设置全局 `NSAllowsArbitraryLoads`，不关闭系统 ATS。

[`BrowserNavigationDelegate`](../CloudFloat/Browser/BrowserNavigationDelegate.swift) 执行策略，并：

- 对服务器信任 challenge 使用 `.performDefaultHandling`（无效证书 → 导航失败并提示，不安装绕过）；
- `shouldAllowDeprecatedTLS` 返回 `false`；
- 记录失败/重定向/HTTP 状态（仅 host/错误码）；
- `webViewWebContentProcessDidTerminate` 通知会话层，不自动重载；
- TLS 错误分类在 [`BrowserSession.swift`](../CloudFloat/Browser/BrowserSession.swift) 的 `TLSErrorClassifier`。

[`BrowserUIDelegate`](../CloudFloat/Browser/BrowserUIDelegate.swift)：

- 将 `target=_blank` / `window.open` 转成新标签页；新标签使用隔离 content controller，避免媒体探测冲突；
- 实现 JS alert/confirm/prompt（所有 completion 都保证调用，避免页面卡死）；
- 拒绝摄像头/麦克风权限；
- 已弃用 TLS 拒绝；弹窗导航同样有 scheme 策略；
- 新标签关闭（JS `window.close` 或用户关闭）只关闭该标签，不刷新主页面；集成测试验证主 WebView 实例不变。

### 2.3 Cookie 与登录状态

[`CookieStore`](../CloudFloat/Browser/CookieStore.swift)：

- 只使用 `WKWebsiteDataStore.dataRecords(ofTypes: [.cookies])` 做域名级记录计数，不读取 Cookie 名称/值或 HttpOnly 内容；
- 显示 Cookie 网站记录总数与不同域名数；不区分“官方/非官方”站点；
- 只有用户在设置中明确确认“清除网站数据”后才调用 `removeData(ofTypes: allWebsiteDataTypes())`；
- 不提供账号密码输入、存储、自动登录或 token 导出。

### 2.4 媒体探测调度（统一 Timer）

`AppCoordinator.updateMediaScheduling()` 是唯一入口：

- 前台且处于浏览器界面：活动标签轮询；
- 若 PiP 来源是另一个标签：该标签也保留轮询（最多 2 个 Timer）；
- 其他后台标签、首页状态、App 进入后台：全部 `stopPolling()`；
- PiP 事件监听来自 `WKScriptMessageHandler`，不依赖轮询，因此后台不受影响。

### 2.5 PiP 全局生命周期

[`PiPManager`](../CloudFloat/Browser/PiPManager.swift)：

- `activePiPTabID` 记录唯一来源；`coordinators[tabID]` 每标签一个协调器；
- 媒体事件按 tabID 路由，切换活动标签不改变来源；
- 关闭来源标签：`beginStopBeforeClose` → `exitPiP()` → 等待页面
  `leavepictureinpicture` → `completeDeferredPiPClose` → `tabs.closeTab(force:true)`；
  1.5 秒未收到事件则超时兜底，避免永远无法关闭；
- `stopObserving` 释放协调器与待关闭标记；
- `AudioSessionManager` 依据全局 `activePiPTabID` 保持激活，不因选中标签变化而误停。

### 2.6 下载

`DownloadManager` 由 `BrowserTabManager` 创建并注入每个 `BrowserSession`，因此：

- 所有标签（包括隐私标签）共用同一个下载队列；
- 切换/关闭标签不会让进行中或已完成的下载从 Downloads UI 消失；
- 下载文件写入 `Documents/Downloads`，支持进度、暂停（WebKit resumeData）、继续、
  取消与系统分享；不读取下载内容、不绕过 TLS。

### 2.7 标签缩略图

[`TabThumbnailCache`](../CloudFloat/Browser/TabThumbnailCache.swift)：

- `WKWebView.takeSnapshot` → PNG → `Caches/Ariuno/TabThumbnails/<tabID>.png`；
- 2 分钟过期，过期后重新截图；
- 标签关闭即删除文件；`clear()` 清空目录；
- 不写入 UserDefaults，不进入备份敏感数据。

## 3. 媒体探测（M2）

### 3.1 注入与观测

[`MediaProbe.js`](../CloudFloat/Media/MediaProbe.js) 通过 `WKUserScript(injectionTime: .atDocumentEnd, forMainFrameOnly: false)` 注入每个 frame。它：

- 只观测 DOM/媒体元素，不修改页面业务 JS；
- 报告 video 数量、playing/paused/ended、readyState、networkState、尺寸、duration、muted/volume、`srcObject`/srcKind、PiP 支持、演示模式、inPiP、DRM 标记、Permissions Policy；
- 报告 canvas/iframe 数量、visibilityState、frame origin（仅 scheme+host+port）；
- 监听 `playing/pause/waiting/stalled/emptied/error/loadedmetadata/loadeddata`、`enterpictureinpicture/leavepictureinpicture/webkitpresentationmodechanged`、`visibilitychange`；
- MutationObserver 观察新增 video/canvas/iframe，去抖后上报快照；
- 不采集完整 media URL；`srcKind` 仅分类为 network/blob/data/mediastream/none；
- 原生侧 [`MediaDetector`](../CloudFloat/Media/MediaDetector.swift) 再做 origin 清洗、字段截断/上限、消息大小上限、frame 数量上限；
- 原生前台低频轮询（3 秒，`Timer` + tolerance，`RunLoop.main.common`）只刷新主 frame，作为兜底；后台停止轮询，不依赖 JS 心跳。

### 3.2 分类

[`MediaEvents.swift`](../CloudFloat/Media/MediaEvents.swift) 定义 `MediaKind`：

- `htmlVideo`：可访问 HTML5 video；
- `webRTCVideo`：video 使用 `srcObject`/MediaStream；
- `canvas`：只有 Canvas/WebGL，没有 video；
- `crossOriginFrame`：只有 iframe，未在可访问 frame 中发现 video；
- `unknown`：尚未发现/受保护渲染。

聚合结果包含 frames、video/playing/PiP-capable 计数、canvas/iframe、origins（脱敏）、最后快照时间、最佳候选视频。

### 3.3 PiP 触发与用户激活

[`WebPictureInPictureCoordinator`](../CloudFloat/Media/WebPictureInPictureCoordinator.swift)：

0. 来源绑定：PiP 属于发起标签；切换到其他标签不会把 PiP 控制器重绑到当前标签。
1. 平台门控：`AVPictureInPictureController.isPictureInPictureSupported()`。
2. 配置门控：`allowsPictureInPictureMediaPlayback`。
3. 探测门控：有快照、有 video、有播放中的视频、video 支持 HTML5 PiP、Permissions Policy 不禁止。
4. 浏览器界面不再提供第二个原生 PiP 悬浮球；能力检测页/测试页仍可通过 `evaluateJavaScript` 调页面 `requestPiP(requestId, videoIndex)`。
5. 唯一的 PiP 入口是网页内控件（Shadow DOM，44pt，默认右上角，可拖动，位置按站点记忆）；它在真实点击事件中同步调用 `webkitSetPresentationMode('picture-in-picture')` 或 `requestPictureInPicture()`；这是 WebKit 认可的路径。
6. 页面回传 `pipResult`，原生等待 requestId、5 秒超时；enter/leave 事件驱动状态机。
7. 用户可在设置中关闭页面内控件；已存在的子 frame 在下次导航后生效（文档已注明）。
8. 若唯一可 PiP 的视频位于跨域子 frame，原生 `evaluateJavaScript` 无法到达；协调器返回 `requiresUserGesture` 并引导使用子 frame 自己的页面内控件，而不是误报“无视频”。
9. 关闭 PiP 只把状态回到 `ready`，不结束游戏、不重载。

失败原因 `PiPFailureReason`：平台不支持、WebView 配置关闭、无视频、视频未播放、网页不支持、需用户手势、Permissions Policy、全屏/投屏占用、探测不可用、超时、未知。用户提示与原因映射有单测。

### 3.4 M4 占位

[`NativePictureInPictureCoordinator`](../CloudFloat/Media/NativePictureInPictureCoordinator.swift) 只有接口：

- `FeatureFlags.nativeMediaPipelineEnabled == false`；
- `startNativePictureInPicture()` 总是抛出 `notImplemented`；
- 状态固定为 `Not Feasible`：缺少官方授权/文档化的独立可解码实时流、输入通道与会话一致性；不使用 `AVSampleBufferDisplayLayer` 作为 WebView 屏幕抓取，不使用私有 API。

## 4. 会话状态与验证（M3）

### 4.1 状态机

[`SessionStateMachine`](../CloudFloat/Session/GameSessionState.swift) 是纯结构体，无 WebKit/UIKit 依赖，所有转移可单测：

```text
idle → loading → ready ↔ pipStarting → pipActive
ready/pipActive → streamStalled → reconnecting → ready
ready/… → disconnected → reconnecting → ready
任何活动态 → failed（WebContent 崩溃/导航失败）
任何活动态 → unsupported（无媒体/平台限制）
任意 → idle（用户退出）
```

关键规则：

- `pipStopped` → `ready`，不进入 failed，不结束页面；
- `pipFailed` → 页面继续运行（ready），只记录非致命错误；
- 后台/前台事件不改变状态，不触发重载；
- 网络丢失时若仍有播放观测则保留 PiP 状态（缓冲帧），否则 disconnected；
- `processTerminated` → failed，清 PiP，必须用户确认才能重载；
- 用户退出重置状态，但保留 WKWebView 网站数据（Cookie/登录）。

### 4.2 三层验证

[`PlaybackVerification`](../CloudFloat/Session/GameSessionState.swift) 明确三件事：

1. `pipVisible`：系统浮窗是否显示（来自网页 enter/leave 事件、快照对账）；
2. `mediaFlowingObserved`：最近是否观测到媒体播放（事件/快照），不等于后台持续存活；
3. `serverSessionVerified`：**恒为 false**。没有公开 API 能证明云端游戏会话、进度或自动战斗仍在运行。

`isFullBackgroundIdleVerified` 仅在三层全部成立时为 true，因此当前代码永远不会返回“挂机成功”；UI 显示 UNVERIFIED 和解释。

### 4.3 前后台

[`AppCoordinator.handleScenePhase`](../CloudFloat/App/AppCoordinator.swift)：

- `.background`：记录时间、停止探测轮询、更新音频会话；不 `reload`；
- `.active`：记录时间、恢复轮询、触发一次前台探测、刷新 PiP 可用性；保留同一 WebView；
- 前台恢复若处于 failed，由错误横幅/恢复提示处理，仍需用户确认重载。

### 4.4 恢复策略

[`RecoveryPolicy`](../CloudFloat/Session/SessionRecovery.swift) 与 [`WebContentRecovery`](../CloudFloat/Browser/WebContentRecovery.swift)：

- **不存在自动 reload 分支**；
- WebContent 崩溃/主框架失败/媒体停滞 → 只生成用户确认提示；
- 网络恢复/返回前台 → 等待现有页面自行恢复，不重载；
- 用户确认重载时做 60 秒冷却、600 秒窗口内最多 3 次限制，避免重复启动云游戏/额外计费；
- 重载前结束 PiP；记录诊断与总尝试次数；
- 单测验证所有非用户触发都不会返回 `reloadNow`。

[`SessionMonitor`](../CloudFloat/Session/SessionMonitor.swift) 把导航/媒体/网络/生命周期事件喂给状态机，并维护最后媒体活动、前后台时间、恢复次数、错误、网络状态、探测轮询状态；停止/恢复 watchdog 只在显式 waiting/stalled 事件后、前台计时，避免把后台 JS 暂停误判为服务器断线。

## 5. 诊断与隐私（M6 支撑）

[`DiagnosticsStore`](../CloudFloat/Diagnostics/DiagnosticsStore.swift)：

- 内存环形缓冲（默认 800 条），满后丢弃最旧；
- 写入时 [`PrivacyRedactor`](../CloudFloat/Diagnostics/PrivacyRedactor.swift) 脱敏：
  - URL → 只留 `scheme://host[:port]`，丢弃 path/query/fragment；
  - Authorization/Cookie/Set-Cookie 整行；
  - `token/uid/password/...` 键值对保留键、值替换；
  - Bearer、JWT、邮箱、手机号、UUID、长 base64/hex 字面量；
  - metadata 敏感键整个值替换，限制条目数与长度；
- 不自动落盘/上传；导出由用户点击 Share/复制触发，写临时文件并加文件保护；分享结束删除临时文件；
- 导出载荷含 app 版本、build、iOS 版本、设备型号（非 UDID）、locale、是否模拟器、会话快照、脱敏事件；
- `DiagnosticsView` 提供筛选、JSON/文本导出、复制、清空；不包含 token/Cookie 值。

## 6. 音频与后台模式

[`AudioSessionManager`](../CloudFloat/Session/AudioSessionManager.swift)：

- 只在“真实媒体播放”或“PiP 可见”时设置 `AVAudioSession` 为 `.playback` 并激活；
- 停止真实播放后延迟 3 秒 deactivate（`.notifyOthersOnDeactivation`）；
- 不播放任何静音音频，不做保活；
- Info.plist 声明 `UIBackgroundModes = ["audio"]`，只用于合规的真实媒体/PiP 音频；说明见 [background-audio.md](background-audio.md)。

## 7. UI 关键点（M5）

- 首页只有“继续游戏 / 画中画能力检测 / 诊断 / 设置”四个入口；非官方说明在页脚。
- `BrowserView`：Safari 式非全屏布局，网页内容与控制栏各占空间；控制栏默认单行（返回/地址/刷新/标签/更多），点击地址栏展开两行，点击网页收回单行。
- 控制栏可一键收起为可拖动液态玻璃悬浮球；悬浮球位置与吸附边持久化，横竖屏/PiP 布局变化后仍吸附原边，3 秒无操作半收并变淡。
- PiP 不可用的页面不再显示占位提示条；能力检测页提供逐项检查与建议。
- 关闭 PiP 后文案明确“游戏会话保留”；退出会话需确认；返回首页保留会话；退出会话保留 Cookie/登录。
- 三层状态卡始终显示服务器会话 UNVERIFIED，并解释人工验证要求。
- 横竖屏由 Info.plist 支持；WebView 忽略安全区保证游戏输入坐标；工具栏/状态卡使用安全区。
- 无官方 Logo、无官方品牌冒充；深浅色自适应、扁平卡片。

## 8. 测试架构

- 单元测试：纯状态机、策略、脱敏、解析、配置、M4 门控。
- 集成测试：真实 `WKWebView` + 真实 `LocalHTTPServer` + 真实探测脚本：
  - 原生视频快照/事件；
  - Canvas 分类；
  - 跨域 iframe 父子独立上报；
  - 页面内控件禁用；
  - 登录弹窗打开/关闭不刷新主页面；
  - HTTP Range/404/路径穿越。
- 本地服务器只绑定 `127.0.0.1` 并只读 TestPages；仅在 Debug/开发工具中使用，测试页面截图与结果见 [qa-matrix.md](qa-matrix.md)。
- 真机/账号相关 T01–T05 等无法在当前环境自动化的项，全部标记 UNVERIFIED 并提供手工步骤/模板。

## 9. 明确不采用的做法

- 私有 WebKit API 获取视频层/PiP 状态；
- `AVSampleBufferDisplayLayer` 屏幕抓取、后台截图转视频；
- 静音音频/位置/VoIP 伪后台；
- 自动注入点击脚本、自动开始下一轮战斗；
- 自动 reload / 无限重连 / 重复启动云会话；
- 读取/导出 Cookie/token、忽略证书错误、绕过登录/DRM；
- 自建服务器或第三方转码。

这些不是“待优化”，而是合规与真实性边界。任何后续实现都应先更新本文档与 [known-limitations.md](known-limitations.md)、补充真机证据。
