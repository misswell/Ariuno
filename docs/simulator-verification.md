# 模拟器验证记录（用户指示模式）

- 记录日期：2026-11-16
- 用户指示：在无法提供真实 iPhone 与授权官方测试账号的情况下，用户明确回复“用模拟器验证啊”。
- 本文件记录**模拟器实际能验证的全部内容**，以及模拟器**不能替代**的真机/账号验收项。
- 结论：模拟器验证通过的范围是“浏览器壳 + 媒体探测 + 状态机/诊断/恢复 + 本地测试页 + Cookie/会话保持”；**T01 真机 PiP、T02 官方登录/游玩、T03 游戏 PiP、T04 后台 PiP/30 分钟、T05 自动战斗仍然 UNVERIFIED**。模拟器不能把这几项变成 PASS，也不能据此宣称后台挂机。

## 1. 环境

| 项目 | 值 |
|---|---|
| Xcode | 27.2（Build 27B52） |
| iOS SDK | 27.2 |
| 模拟器 | iPhone 17 Pro，iOS 26.3.1 |
| 真实 iPhone | 无 |
| 授权米哈游账号 | 无（未输入任何凭证） |
| 系统 PiP | `AVPictureInPictureController.isPictureInPictureSupported() == false` |
| 官方入口 | 未登录壳可打开并显示登录面板；未登录/未游玩 |

## 2. 自动化验证

```bash
xcodebuild \
  -project Ariuno.xcodeproj \
  -scheme Ariuno \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=4F2CA7A5-367C-4D1F-B6E1-AC0D8766DC69' \
  -derivedDataPath build/DerivedData \
  test
```

结果：`Executed 142 tests, with 0 failures`，`** TEST SUCCEEDED **`。

覆盖（详见 [qa-matrix.md](qa-matrix.md)）：

- 本地视频页：快照、播放/媒体事件、HTML5 PiP 能力上报；
- Canvas 页：分类为 `canvas`，无 video；
- 跨域 iframe：两个端口、父/子 frame 独立上报；子 frame 视频不误判为主 frame；
- 登录弹窗：真实 `WKUIDelegate` Popup 打开，关闭后主 WebView 不重建/刷新；
- T09：跨 `BrowserSession`/`WKWebView` 实例的 WebKit Cookie 持久化；
- T11：可重建的 SwiftUI `RootView` host 重建、首页/游戏往返后同一 WebView，页面 JS 标记保留；
- 状态机/恢复：前后台、网络、崩溃、无自动 reload、冷却/上限；
- 导航白名单/外部 URL/危险 scheme/TLS 分类；
- 隐私脱敏、诊断导出、本地 HTTP Range/404/路径穿越。

## 3. Safari vs WKWebView（模拟器）

在同一个模拟器：

- Safari 打开 `https://sr.mihoyo.com/cloud/`，显示与 WKWebView 相同的官方登录面板（手机号/验证码、账号密码登录入口），未输入任何凭证；
- App 的 WKWebView 打开同一入口，也显示登录面板（见 [official-entry-wkwebview.png](images/official-entry-wkwebview.png)）；
- Safari 截图：[official-entry-safari-simulator.png](images/official-entry-safari-simulator.png)。

结论：在**未登录**阶段，模拟器 Safari 与 WKWebView 都能加载官方入口壳，未观察到入口级拒绝。该结果不证明登录后/游玩/媒体/PiP 兼容，也不能替代真机 Safari/WKWebView 对照（T02 仍 UNVERIFIED）。

## 4. UI/运行时检查

| 截图 | 观察 |
|---|---|
| [home.png](images/home.png) / [home-dark.png](images/home-dark.png) | 首页四入口、深浅色、模拟器 PiP 不支持提示 |
| [test-pages.png](images/test-pages.png) | 本地视频播放、时间码、探测计数、HTML5 PiP 不支持 |
| [official-entry-wkwebview.png](images/official-entry-wkwebview.png) | 未登录官方入口在 WKWebView 中显示登录面板；无凭证 |
| [official-entry-safari-simulator.png](images/official-entry-safari-simulator.png) | 同一模拟器的 Safari 也显示登录面板；仅壳对比，未登录/未游玩 |
| [capability-check.png](images/capability-check.png) | 平台/配置/探测门控与三层状态 |
| [settings.png](images/settings.png) | 工具栏、PiP、音频、域名级 Cookie 记录 |
| [diagnostics.png](images/diagnostics.png) | 会话/媒体/日志/导出 |

## 5. 模拟器后台/前台生命周期实测（T04-lite）

这不是 T04 的通过证据，只验证“App 进入后台再回前台时，Session 的 WebView/page 不被重建/重载”。

执行：

1. 启动 App，`-CFOpenLocalGame` 加载本地视频页；
2. 等待页面播放，记录 PID 与截图；
3. 启动系统 Settings 把 Ariuno 切到后台；
4. 等待 **60 秒**；
5. 通过 `simctl launch` 把 Ariuno 唤回前台（不 terminate）；
6. 截图/记录 PID、页面、视频当前时间。

| 指标 | 后台前 | 后台 60 秒后回前台 |
|---|---|---|
| App PID | 5463 | **5463（同一进程）** |
| 页面 | `native-video.html`，480×270，视频播放中 | **同一页面，未刷新/未重建** |
| HTML5 PiP 支持 | 不支持（模拟器） | 不支持（模拟器） |
| 视频当前时间 | 3.7 s | 15.6 s（后台期间未持续播放，回前台后可继续） |
| 操作 | 播放/暂停、重新加载等按钮可用 | 同一 WebView，按钮仍可用 |

截图：[后台前](images/simulator-lifecycle-before.png)、[后台 1 分钟后](images/simulator-lifecycle-after-1min.png)。

解释：

- 模拟器没有 PiP，视频在后台被系统暂停/节流是预期行为；不能据此证明后台画面持续。
- 该测试证明了“后台不 reload、WebView 未重建、返回后页面还在”，与 M1/M3 的“不得因后台重载”一致。
- 因为**没有 PiP、没有官方游戏、没有服务器会话**，它不能替代 T04 的 1/5/15/30 分钟验收，更不能证明自动战斗持续。30 分钟×3 未执行。

## 6. 模拟器不能验证的项

| 项目 | 原因 | 状态 |
|---|---|---|
| T01 普通视频真机 PiP | 模拟器不支持系统 PiP；无法进入浮窗 | UNVERIFIED |
| T02 官方登录/游玩 | 无授权账号；未输入凭证 | UNVERIFIED（仅壳可达） |
| T03 游戏实时画面 PiP | 无官方游戏会话/媒体 | UNVERIFIED |
| T04 后台 PiP 1/5/15/30 分钟 | 无 PiP、无官方游戏；模拟器不等价 | UNVERIFIED（仅完成 T04-lite 生命周期） |
| T05 自动战斗持续 | 无账号、无游戏进度；不得伪造 | UNVERIFIED |
| T09 官方登录跨 App 重启保持 | 仅验证了 WebKit Cookie 跨实例持久化；官方服务器策略未知 | PARTIAL / UNVERIFIED |
| T11 真机 PiP 返回 | 仅验证 SwiftUI host 重建/首页往返；真实 PiP 未验证 | PARTIAL / UNVERIFIED |
| T12 真机内存/CPU/耗电 | 模拟器无法代表真机资源/热/功耗 | UNVERIFIED |

## 7. 真机结果补充

后续已连接 iPhone 15 Pro 完成真机验证：T01/T02/T03/T09 有 PASS 证据；T04/T05 在约 15 分钟无输入后被服务器以 -1022 断开，FAIL。详见 [real-device-verification.md](real-device-verification.md)。模拟器记录继续作为工程/媒体探测证据，但不能替代真机结论。

## 8. 用户范围指示与结论

用户于 2026-11-16 指示“用模拟器验证啊”。据此已完成模拟器可执行的验证并记录本文件；这**不改变任务书对 T02/T03/T05/30 分钟阻断项的要求**。

- 若目标是“浏览器 + 诊断原型（模拟器验证）”：本仓库已满足，证据见上。
- 若目标是任务书原定义的“真机 PiP/后台挂机验收”：仍必须提供真实 iPhone 与授权官方账号，按 [manual-verification-template.md](manual-verification-template.md) 执行；当前不能声明达成。
