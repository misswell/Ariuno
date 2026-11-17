# Ariuno 实施报告

- 报告日期：2026-11-16
- 工程：当前仓库根目录（Ariuno，源码目录保留 `CloudFloat/`）
- 版本：0.1.0（Build 1）
- 结论：**M0–M6 的工程与自动化部分已完成；真机 iPhone 15 Pro 已验证 T01/T02/T03/T09（本地视频 PiP、官方登录/进入游戏、游戏实时 PiP、登录保持），但 T04/T05 因服务器空闲超时（错误码 -1022）FAIL。不得声称后台挂机；交付为浏览器 + 诊断原型。**

## 1. 里程碑状态

| 里程碑 | 状态 | 证据 |
|---|---|---|
| M0 技术预研 | **真机部分通过 / 后台挂机 FAIL** | 真机登录、进入游戏、实时 PiP、自动战斗推进已验证；约 15 分钟无输入后服务器断开（-1022），T04/T05 FAIL。见 [feasibility.md](feasibility.md)、[real-device-verification.md](real-device-verification.md) |
| M1 稳定浏览器内核 | **实现并自动化验证** | 多标签 WebView、M1 配置、UA 不伪造、Cookie 持久化、导航策略、外部 URL、弹窗、TLS 默认处理/拒绝弃用 TLS、崩溃/失败回调。`BrowserSessionTests`/`BrowserTabManagerTests`/`BrowserNavigationTests`/`LoginPopupIntegrationTests` |
| M2 媒体探测与 HTML5 PiP | **实现；真机实时 PiP 单次通过** | 全 frame 注入 `MediaProbe.js`；video/canvas/iframe/readyState/PiP/事件；`MediaKind`；页面内 PiP 控件；原生触发失败映射；真机本地视频与游戏自动战斗 PiP 实测。`MediaProbeTests`/`MediaProbeIntegrationTests`/`WebPictureInPictureTests` |
| M3 后台会话验证与状态机 | **实现；真机后台 FAIL（服务器空闲超时）** | 10 个状态、三层验证、前后台不重载、网络/崩溃事件、诊断、用户确认恢复；真机 15 分钟无输入被服务器断开（-1022），未绕过。`GameSessionStateTests`/`SessionMonitorTests`/`SessionRecoveryTests` |
| M4 原生媒体扩展 | **Not Feasible（仅接口）** | `NativePictureInPictureCoordinator` 固定不可用；无私有 API/屏幕抓取/伪后台 |
| M5 产品界面 | **实现；模拟器视觉检查** | 起始页地址栏/书签、BrowserView 地址栏、多标签页、书签、前进/后退/刷新、自动隐藏工具栏、PiP 原因、诊断/设置/能力检测、深浅色；截图见下 |
| M6 测试与发布 | **自动化通过；真机 T04/T05 FAIL，发布前需按失败结论降级** | 222 项自动化测试通过；真机 T01/T02/T03/T09 PASS，T04/T05 FAIL（-1022）；30 分钟×3 未通过；不得按“后台挂机”上架。见 [qa-matrix.md](qa-matrix.md) |

## 2. 构建结果

实际命令：

```bash
cd <repo-root>
xcodegen generate
xcodebuild \
  -project Ariuno.xcodeproj \
  -scheme Ariuno \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=4F2CA7A5-367C-4D1F-B6E1-AC0D8766DC69' \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

结果：`** BUILD SUCCEEDED **`（Xcode 27.2 / Build 27B52，iOS 27.2 SDK，iPhone 17 Pro 模拟器 iOS 26.3.1）。

构建产物检查：

- `Ariuno.app/MediaProbe.js` 存在；
- `Ariuno.app/TestPages/` 包含 `native-video.html`、`canvas-only.html`、`nested-iframe.html`、`login-popup.html`、`popup-target.html`、`index.html`、`sample.mp4`；
- `PrivacyInfo.xcprivacy` 存在；
- 资源目录/图标编译成功。

唯一构建警告为 Xcode 的 AppIntents 元数据提示（工程不使用 AppIntents），无代码警告。

## 3. 自动化测试结果

```bash
xcodebuild \
  -project Ariuno.xcodeproj \
  -scheme Ariuno \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=4F2CA7A5-367C-4D1F-B6E1-AC0D8766DC69' \
  -derivedDataPath build/DerivedData \
  test
```

结果：

```text
Executed 222 tests, with 0 failures (0 unexpected)
** TEST SUCCEEDED **
```

套件明细：

| 套件 | 数量 |
|---|---:|
| BrowserNavigationTests | 11 |
| BrowserPrivacyTests | 3 |
| BrowserSessionTests | 7 |
| BrowserTabManagerTests | 7 |
| DiagnosticsStoreTests | 8 |
| GameSessionStateTests | 16 |
| HistoryStoreTests | 4 |
| LocalHTTPServerTests | 7 |
| LoginPopupIntegrationTests | 1 |
| MediaProbeIntegrationTests | 7 |
| MediaProbeTests | 14 |
| PrivacyRedactorTests | 10 |
| RecentlyClosedStoreTests | 3 |
| SessionMonitorTests | 9 |
| SessionPersistenceTests | 2 |
| SessionRecoveryTests | 12 |
| URLInputParserTests | 10 |
| BrowserFeatureTests | 5 |
| DownloadManagerTests | 13 |
| AppCoordinatorStartPageTests | 6 |
| WebPictureInPictureTests | 6 |
| TabSessionStoreTests | 5 |
| BrowserTabPersistenceTests | 8 |
| MediaSchedulingTests | 7 |
| PiPSourceCloseTests | 6 |
| TabThumbnailCacheTests | 4 |
| BrowserContainerTests | 2 |
| BrowserPerformanceTests | 3 |
| **合计** | **222** |

高价值集成测试的实际覆盖：

- 真实 `WKWebView` 加载本地视频页，脚本消息桥收到 snapshot；视频在模拟器中播放（测试页 HUD 显示时间码）；
- `playing/loadedmetadata/loadeddata` 媒体事件到达原生；
- Canvas 页面被分类为 `.canvas`，无 video；
- 两个不同端口回环服务器的跨域 iframe：父/子 frame 分别上报，视频在子 frame 被发现；
- 页面内 PiP 控件禁用时不创建 DOM 控件；
- target=_blank/window.open 样例通过真实 `WKUIDelegate` 创建新标签；关闭该标签后主 `WKWebView` 实例不变、主页面不刷新；
- 跨 `BrowserSession` 实例的 WebKit Cookie 持久化；SwiftUI `RootView` host 重建、首页/游戏往返后同一 `WKWebView` 且页面 JS 标记保留（`SessionPersistenceTests`）；
- 本地 HTTP Range（206）、404、路径穿越不被 200 服务；
- 所有非用户触发的恢复策略都不会返回自动 reload。

## 4. 运行时/视觉检查（模拟器）

这些截图仅用于 UI/管线检查，不是官方游戏验证：

| 截图 | 内容 |
|---|---|
| [home.png](images/home.png) | 首页四入口、非官方说明、模拟器 PiP 不支持提示 |
| [test-pages.png](images/test-pages.png) | 测试页实验室：本地视频播放/时间码、探测计数、模拟器 PiP 不支持 |
| [official-entry-wkwebview.png](images/official-entry-wkwebview.png) | 未登录官方入口在 WKWebView 中显示登录面板；未输入凭证 |
| [game-view.png](images/game-view.png) | 真实 BrowserView 外壳 + 本地测试页（非官方游戏） |
| [capability-check.png](images/capability-check.png) | 平台/配置/探测门控与三层状态 |
| [settings.png](images/settings.png) | 工具栏、PiP、音频、隐私设置 |
| [diagnostics.png](images/diagnostics.png) | 会话快照、三层状态、日志入口 |
| [simulator-lifecycle-before.png](images/simulator-lifecycle-before.png) / [after](images/simulator-lifecycle-after-1min.png) | 模拟器 60s 后台/前台：同一 PID/WebView，页面不重建（T04-lite，不是 T04） |

实际运行中还发现并修复了：

- WKWebView 测试页在 `-apple-system` 优先的字体栈下中文显示为缺字方框；改为 CJK 优先字体栈后正常（集成测试同时校验 UTF-8 文本）；
- `SessionMonitor.appIsForeground` 未从状态机同步到 UI；
- 能力检测页使用不存在的 `pip.slash` SF Symbol 导致空白图标；
- 游戏视图隐藏到首页时仍强制隐藏状态栏；
- PiP 进入后快照竞态可能误判退出（加入 2 秒稳定窗口与快照时间比较）。

## 5. 交付物映射（任务书第 7 节）

| 交付物 | 位置/证据 | 状态 |
|---|---|---|
| 1. 可通过 Xcode 构建的完整源码与工程配置 | `project.yml`、`Ariuno.xcodeproj`、`CloudFloat/`；构建日志 `build/test-final.log` / `build/release-final.log` | ✅ 已验证构建 |
| 2. 模拟视频测试页与真机使用说明 | `CloudFloat/TestPages/`、[qa-matrix.md](qa-matrix.md)、[feasibility.md](feasibility.md) | ✅ 页面/说明已交付；真机 T01/T02/T03/T09 已执行 |
| 3. `docs/feasibility.md`（真实设备、实际观察、失败截图/日志、结论） | [feasibility.md](feasibility.md)、[real-device-verification.md](real-device-verification.md) | ✅ 含 iPhone 15 Pro 真机登录/游戏/PiP、15 分钟空闲断开 -1022 失败截图与结论 |
| 4. 浏览器入口、PiP 探测、状态机、异常恢复、诊断导出 | `Browser/`、`Media/`、`Session/`、`Diagnostics/`、`UI/` | ✅ 实现 + 自动化 |
| 5. 测试矩阵、自动化结果、`known-limitations.md` | [qa-matrix.md](qa-matrix.md)、[known-limitations.md](known-limitations.md)、222 tests | ✅ 自动化 + 真机 T01/T02/T03/T09 PASS、T04/T05 FAIL 记录 |
| 6. 隐私说明、后台音视频说明、审核风险清单 | [privacy.md](privacy.md)、[background-audio.md](background-audio.md)、[app-review-risk.md](app-review-risk.md) | ✅ 文档已交付；发布前确认待做 |

## 6. 关键设计决策

1. **HTML5 Web PiP 优先，不做 M4 私有替代**：网页没有 video/PiP 时如实禁用并解释；M4 标记 Not Feasible。
2. **不自动 reload**：会话/崩溃/断网恢复全部需要用户确认，避免重复启动云游戏与额外计费；策略有冷却/上限。
3. **三层验证分离**：PiP 浮窗、媒体实时观测、服务器会话分别展示；服务器会话恒为 UNVERIFIED，避免把 JS/最后一帧当挂机证据。
4. **多标签生命周期**：`BrowserTabManager` 持有各标签 `WKWebView`；切换标签只切换可见性，不重建 WebView/不重载页面。
5. **每 frame 探测 + origin 脱敏**：父页面不越权读跨域 DOM；media URL/path/query 永不进入原生日志。
6. **前台低频轮询、后台停止**：事件驱动为主，3 秒主 frame 兜底；不依赖 JS 心跳。
7. **登录弹窗隔离**：Popup 使用独立 content controller，共享网站数据；关闭不刷新主页面。
8. **后台音频只在真实媒体/PiP 时启用**：不播放静音音频；在审核文档中明确 2.5.4 风险。

## 7. 尚未完成/需要用户执行的事项

发布方需要在有真实 iPhone 与官方账号的授权环境中执行：

1. 真机 Safari 与 WKWebView 同机对照（U06）；
2. Web Inspector/诊断导出完整媒体结构（U02）；
3. 锁屏/来电/耳机/低电量/内存压力/横竖屏/低 iOS 版本矩阵（U07/U08）；
4. 隐私导出抽查、审核条款与米哈游服务条款/品牌授权确认；
5. T04/T05 已 FAIL（服务器空闲断开 -1022）；如不接受该结果，需要官方授权/协议层面的会话保持方案，不能靠客户端绕过。

用户已于 2026-11-16 指示“用模拟器验证啊”。据此完成了 [simulator-verification.md](simulator-verification.md) 中的模拟器可执行项；真实 iPhone/授权账号仍缺失，T02/T03/T04/T05 不能转为 PASS，交付仍按“模拟器验证的浏览器 + 诊断原型”表述，不得宣称后台挂机。

在这些完成前，README、App 内文案与所有文档均保持“未验证、不宣称后台挂机”的措辞。

## 8. 复现步骤

```bash
# 1. 生成工程
xcodegen generate

# 2. 构建
xcodebuild -project Ariuno.xcodeproj -scheme Ariuno -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.3.1' \
  -derivedDataPath build/DerivedData test

# 3. 模拟器手动检查
xcrun simctl boot 'iPhone 17 Pro'
xcrun simctl install booted build/DerivedData/Build/Products/Debug-iphonesimulator/Ariuno.app
xcrun simctl launch booted com.cloudfloat.app -CFOpenTestLab
# 或 -CFOpenLocalGame / -CFOpenOfficialEntry / -CFOpenCapability
```

真机构建请在 Xcode 中设置 Team；Debug 启动参数仅用于开发/QA，Release 不提供测试入口。

## 9. 证据与日志

- `build/test-final.log`：最终 Debug 测试/构建输出（222 tests, 0 failures）。
- `build/release-final.log`：最终 Release 构建输出（BUILD SUCCEEDED）。
- `build/analyze.log`：静态分析输出（ANALYZE SUCCEEDED）。
- `docs/images/`：打码/无凭证的模拟器与真机截图。
- `docs/images/device/`：真机登录面板、本地视频 PiP、脱敏游戏战斗、15 分钟空闲断开（-1022）证据。
- `docs/real-device-verification.md`：真机 T01/T02/T03/T09 PASS、T04/T05 FAIL 的完整记录。
- `artifacts/`：原始截图（含账号标识，仅本地、已被 `.gitignore`；不得分享）。
- 发布前不得提交账号/凭证/完整 token URL；真机原始截图必须脱敏。

## 10. 最终声明

Ariuno 当前交付的是**可构建、可测试、隐私优先的浏览器与 PiP 能力/会话诊断原型**：

- 真机已验证本地网页视频 PiP 5 分钟、官方登录/进入游戏、游戏自动战斗实时 PiP、登录跨升级保持；
- 真机后台约 15 分钟无输入后被服务器主动断开（-1022），因此 T04/T05 FAIL；
- 它不会声称后台挂机成功，也不会用自动点击/伪造输入/私有 API 绕过服务器空闲超时；
- 发布方若继续追求“后台挂机”目标，必须先取得服务器/授权层面的可行方案，否则只能按本原型交付。
- 用户已于 2026-11-16 明确接受缩小范围；见 [scope-acceptance.md](scope-acceptance.md) 与 [scope-status.md](scope-status.md)。
