# 已知限制与 UNVERIFIED 清单

本文件是交付物的一部分，必须与 App 内文案一致。当前结论：**浏览器 + 媒体探测 + 诊断/恢复原型可构建、可测试；真机 T01/T02/T03/T09 已有 PASS 证据，但 T04/T05 因服务器空闲超时 FAIL，不能声称后台挂机。**

验证过程：2026-11-16 先按用户指示完成模拟器验证（[simulator-verification.md](simulator-verification.md)），随后连接 iPhone 15 Pro 完成真机验证（[real-device-verification.md](real-device-verification.md)）。真机游戏自动战斗 PiP 可显示实时画面，但约 15 分钟无输入后服务器主动断开（错误码 -1022），T04/T05 FAIL。用户已明确接受“浏览器 + 诊断原型”缩小范围（[scope-acceptance.md](scope-acceptance.md)）。

## 1. 最高优先级：未验证事项（UNVERIFIED）

| 编号 | 事项 | 当前状态 | 影响 | 需要的证据 |
|---|---|---|---|---|
| U01 | 官方云游戏在真实 iPhone WKWebView 中登录/游玩 | **PASS（iPhone 15 Pro / iOS 27.2.1，单次）** | 其他 iOS/设备/网络组合仍需复测 | 补充较低 iOS 真机 T02 |
| U02 | 登录后游戏媒体路径 | **PARTIAL**：游戏画面可进入 HTML5 PiP，说明存在可 PiP 媒体节点；具体 MediaKind/帧数待诊断导出 | 媒体类型细节未完整记录 | Web Inspector/诊断导出 |
| U03 | 游戏页 HTML5 PiP 能力 | **PASS（单次约 5 分钟）**：游戏自动战斗 PiP 已出现，切后台可见实时战斗与伤害推进 | 长期会话不等于 PiP 成功 | T03；长期见 U04 |
| U04 | 后台 1/5/15/30 分钟媒体与云会话持续 | **FAIL**：1/5 分钟 PiP 保持且战斗推进；约 15 分钟无输入后游戏提示“长时间未操作游戏，已中断连接，错误码 -1022”，PiP 结束 | 未达到 30 分钟；不能宣称挂机 | 3 次 30 分钟记录 + 游戏真实进度 |
| U05 | 自动战斗在无输入/后台时持续 | **FAIL**：第 1 次战斗从进行到胜利结算，随后服务器空闲断开；仅 1 次且会话未持续 | 不能只看视频/浮窗 | T05 至少 3 次且会话持续 |
| U06 | Safari 与 WKWebView 在同一真机的行为差异 | UNVERIFIED（仅模拟器 Safari 壳对比） | 可能差异 | 真机双环境对照 |
| U07 | 锁屏/息屏/来电/耳机/低电量/内存压力下 PiP 与音频 | **PARTIAL**：30 分钟节点设备锁屏、无 PiP；其余场景未做 | 锁屏不等同后台 PiP 存活 | 真机场景矩阵 |
| U08 | 低 iOS 主要版本的兼容性 | UNVERIFIED | 仅模拟器 iOS 26.3.1 + 工程 17.0 目标 | 至少一个较低主要版本真机 |
| U09 | 长时间内存/CPU/耗电 | UNVERIFIED | 可能内存线性增长或后台耗电 | Instruments/真机 T12 |

## 2. 技术限制（公开 API/系统行为）

### 2.1 PiP 需要用户手势

- WebKit 进入 HTML5 PiP 通常要求来自网页内容的真实用户激活；原生 `evaluateJavaScript` 往往没有 transient activation。
- 处理：原生按钮失败时映射为 `requiresUserGesture`，页面内显示 44pt PiP 控件；用户需点击网页内控件。不是无感/自动进入。
- 限制：页面内控件只在有“正在播放且支持 PiP”的视频时出现；模拟器不支持 PiP；某些页面/iframe Permissions Policy 会禁止。
- 用户可见：按钮禁用并显示原因；失败弹窗说明；不会伪报成功。

### 2.2 系统 PiP 小窗不可直接操作游戏

- iOS PiP 浮窗通常只显示视频；触控需要点小窗回到 App。
- 本 App 不实现（也无法通过公开 API 实现）在 PiP 小窗内注入游戏触控。

### 2.3 后台 JS/WebSocket 可能被挂起

- iOS 可能暂停 WebContent 的 JS 定时器、WebSocket/WebRTC 事件循环；PiP 只保证媒体层可能继续，不保证页面逻辑、自动战斗或服务器会话继续。
- 本 App 不把 JS 心跳、`document.visibilityState` 或最后一帧当作服务器在线证明；进入后台停止探测轮询。
- 用户可见：服务器会话始终 `UNVERIFIED`；后台状态只显示“最近观测”。

### 2.4 服务器端会话无法由公开 API 证明

- 没有公开 API 可查询米哈游云游戏会话、战斗进度或空闲超时。
- `PlaybackVerification.serverSessionVerified` 恒为 false；只有用户返回游戏人工确认进度变化，才能作为人工证据（不是 App 自动证明）。
- 因此 `isFullBackgroundIdleVerified` 永远不成立；UI 不会显示“已挂机”。

### 2.5 Canvas/WebGL 无法进入 HTML5 PiP

- 如果游戏画面只渲染在 canvas/WebGL 且没有 video 元素，系统 HTML5 PiP 无从接管。
- App 会分类为 `canvas`，PiP 按钮禁用并说明“页面中没有可用视频”。
- 不采用屏幕抓取/后台截图转视频（任务书禁止，且不是合法/稳定的 PiP 来源）。

### 2.6 跨域 iframe

- 父页面不能读取跨域子 frame DOM；只能依靠注入到每个 frame 的独立探测脚本上报。
- 若子 frame 没有注入（平台/策略/时序）或媒体在受保护渲染中，父页面只能看到 `crossOriginFrame/unknown`。
- 子 frame 的 Permissions Policy 可能禁止 PiP；探测会报告 `pipFeatureAllowed=false`。
- 原生 `evaluateJavaScript` 只能作用于主 frame。若可 PiP 的视频只在跨域子 frame，原生按钮会如实返回“需要网页内点击”，用户必须使用该子 frame 视频右上角的页面内 PiP 控件；设置关闭该控件时需先开启并让子 frame 重新导航。
- 设置关闭页面内控件后，已存在的子 frame 需下次导航才完全生效。

### 2.7 DRM/EME 与受保护媒体

- 若视频受 DRM/EME 保护，`requestPictureInPicture` 可能被拒绝；探测只读取 `mediaKeys/webkitKeys` 布尔值，不解密、不抓取内容。
- 不绕过 DRM/授权；若受保护导致无法 PiP，标记为不支持。

### 2.8 模拟器

- iOS 模拟器通常 `AVPictureInPictureController.isPictureInPictureSupported() == false`；本地测试页的 HTML5 PiP 也不会真正进入系统浮窗。
- 模拟器可验证 DOM 探测、状态机、页面加载、弹窗、日志、布局，但不能证明真机 PiP/后台/音频。

### 2.9 官方网页的 WKWebView/设备检测

- 未登录入口在 iOS 26.3.1 模拟器 WKWebView 中能显示登录面板；**不代表**登录后、真机、或所有地区/账号不会被拒绝。
- 若官方页面拒绝 WKWebView 或提示设备不支持，App 只能如实显示错误/待验证，不伪造 UA 绕过设备检测。

### 2.10 后台音频

- `UIBackgroundModes: audio` 与 `AVAudioSession .playback` 只在真实媒体播放或 PiP 可见时使用；不播放静音音频。
- 如果用户关闭该设置，后台音频可能停止，但视频/PiP 行为由 WebKit/系统决定。
- App Review 2.5.4 可能审查后台音频用途；详见 [background-audio.md](background-audio.md) 与 [app-review-risk.md](app-review-risk.md)。

### 2.11 恢复与重连

- 没有自动重载；所有 reload 需用户确认，并有 60 秒冷却、10 分钟内最多 3 次限制，避免重复启动云游戏产生额外时长。
- 用户确认重载仍可能重新开始云游戏会话；App 不能保证恢复原战斗进度。
- WebContent 崩溃后，系统 PiP 可能已结束；App 不伪造浮窗。

### 2.12 外部链接与弹窗

- 主框架非官方 https 链接点击会先确认再交给系统浏览器；不直接在游戏 WebView 加载，避免页面被替换。
- `mailto/tel/sms/facetime` 同样需用户确认；`itms-services`、自定义 scheme、`javascript/data/blob/file` 阻止。
- 登录弹窗使用独立 content controller，不参与游戏媒体探测；若弹窗内需要特殊文件上传/支付/摄像头权限，可能不可用（摄像头/麦克风默认拒绝）。

### 2.13 测试资产

- `TestPages/native-video.html` 使用合成 H.264/AAC 视频（`sample.mp4`），不是官方游戏内容；页面的“HTML5 PiP 支持”反映当前设备/浏览器，不代表官方网页。
- 本地回环 HTTP 服务只绑定 `127.0.0.1`，只在 Debug/开发者工具中可达；Release 无入口。它不承载官方会话，也不应用于生产。

### 2.14 诊断

- 诊断只在内存（默认 800 条），不自动持久化/上传；App 重启后丢失。
- 脱敏是尽力而为，不是“可以记录秘密”的许可；调用点仍不得读取 Cookie/token/完整 URL。
- 设备型号（如 iPhone17,1）会出现在导出中；不包含 UDID/序列号。
- 导出文件写到临时目录，分享结束后删除；若用户另存，后续保管责任在用户。

### 2.15 云游戏服务器空闲超时（已实测）

真机 iPhone 15 Pro、iOS 27.2.1、Wi-Fi/5G/VPN：游戏自动战斗 + PiP 后台约 15 分钟后，游戏网页自身显示：

> 连接中断 / 因为您长时间未操作游戏，已中断连接 / 错误码：-1022

- 这是云游戏服务器/客户端的空闲策略，不是 App 的 WebView 崩溃；本 App 没有也不应通过自动点击、伪造输入、静音音频或私有 API 绕过。
- 30 分钟节点设备已锁屏，PiP 不存在；锁屏/息屏场景同样不能作为后台挂机证据。
- PiP 只能维持网页媒体的系统浮窗，不能替用户产生游戏输入，也不能阻止服务器回收空闲会话。
- 结论：在当前规则下，**无输入后台挂机（T04/T05）不可实现**；只能交付浏览器 + 诊断原型，并如实提示用户定期返回操作。

### 2.16 真机布局/交互

- 已在 iPhone 17 Pro 模拟器竖屏检查；横屏、较小屏幕、动态岛、iPad 分屏、外接键盘未全面人工验证。
- WebView 使用 `ignoresSafeArea` 以保持游戏输入坐标；游戏自身若不适配刘海/动态岛，内容可能被遮挡（这是网页行为）。
- 页面内 PiP 控件位于右上角，可能覆盖游戏自身按钮；可在设置关闭，或等待页面内控件消失（无播放/已 PiP 时自动移除）。

## 3. M4：原生媒体管线 Not Feasible

[`NativePictureInPictureCoordinator`](../CloudFloat/Media/NativePictureInPictureCoordinator.swift) 仅保留接口，状态固定：

> **Not Feasible：缺少官方授权与文档化的独立实时媒体流；不以私有 API、屏幕抓取或伪造后台权限替代。**

原因：

1. 没有官方授权、文档化的独立可解码实时媒体流；
2. 没有授权输入通道与云会话一致性保证；
3. `AVSampleBufferDisplayLayer` 不能作为任意 WKWebView 的屏幕抓取；
4. 使用私有 API/伪造视频通话 PiP 类型属于违规。

若未来获得正式授权与文档，需要重新评估解码器、音频、时间戳、网络恢复、输入通道、会话一致性和 App Review，不能直接打开当前占位实现。

## 4. 合规/上架限制

- Ariuno 是非官方浏览器工具，不使用官方 Logo 冒充客户端；上架前需确认品牌/内容授权与米哈游服务条款。
- 云游戏登录/游玩受官方服务条款约束；“后台挂机”可能触及游戏/服务条款与反作弊政策，需法律/合规确认。
- App Review 2.5.4 对后台模式用途有约束；本 App 只在真实媒体/PiP 时使用音频后台能力，仍需审核解释。
- 若 T02/T03/T05/30 分钟证据未完成，不得在 App 描述、截图、TestFlight 说明或宣传中使用“支持后台挂机/自动战斗持续”等表述。
- 本仓库不包含账号、凭证、官方素材或测试账号；真实测试由发布方在授权范围内完成。

## 5. 明确不会实现（不是 TODO）

- 自动开始下一轮战斗、自动点击、脚本化操作；
- 静音音频/位置/VoIP/后台截图转视频保活；
- 私有 API 获取 WebView 视频层或 PiP 状态；
- 绕过米哈游登录/设备检测/反作弊/DRM；
- 自建服务器、第三方转码、把账号密码输入非官方页面；
- 忽略证书错误或自动信任异常证书；
- 通过自动 reload/无限重连维持会话（避免重复计费和会话破坏）。

## 6. 结论

真机已完成 T01/T02/T03/T09 的单次/5 分钟级验证；T04/T05 因服务器空闲超时（-1022）FAIL。因此本项目只能作为：

- 稳定的官方网页浏览器壳；
- 媒体/PiP 能力探测与如实原因反馈（含 5 分钟实时 PiP）；
- 会话状态机、诊断和“用户确认后恢复”的安全原型。

**不得**作为“可后台挂机”的成品或宣传依据；若服务器策略不改变，本项目不应继续尝试绕过空闲超时。
