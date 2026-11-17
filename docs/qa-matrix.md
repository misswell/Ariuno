# Ariuno 测试矩阵与验收记录

- 版本：0.1.0（Build 1）
- 最近自动化执行：2026-11-16
- 环境：Xcode 27.2 / iOS 27.2 SDK / iPhone 17 Pro 模拟器（iOS 26.3.1）
- 状态图例：
  - ✅ **PASS**：当前环境已自动化验证
  - ◐ **PARTIAL**：代码/单元测试已验证，真实设备/真实游戏未验证
  - ⬜ **UNVERIFIED**：缺少真机、账号、游戏会话或后台证据
  - ⛔ **BLOCKED / NOT FEASIBLE**：公开 API 或授权条件不满足，不能实现或不能声称成功

> 重要：自动测试通过不等于《云·星穹铁道》支持 PiP 或后台挂机。真机 T05 已 FAIL（15 分钟空闲断线 -1022），不得交付“可后台挂机”结论。
>
> 验证过程：2026-11-16 先按用户指示完成模拟器验证（[simulator-verification.md](simulator-verification.md)），随后在 iPhone 15 Pro 真机完成 T01/T02/T03/T09；真机 T04/T05 在约 15 分钟无输入后被服务器以 -1022 断开，记录为 FAIL。用户已明确接受“浏览器 + 诊断原型”缩小范围（[scope-acceptance.md](scope-acceptance.md)）；T04/T05 保持 FAIL。详见 [real-device-verification.md](real-device-verification.md)。

## 1. 自动化测试结果

命令：

```bash
xcodegen generate
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
Executed 201 tests, with 0 failures (0 unexpected)
** TEST SUCCEEDED **
```

| 测试套件 | 数量 | 覆盖重点 |
|---|---:|---|
| BrowserNavigationTests | 11 | 通用 HTTP/HTTPS 站内导航、本地测试页、外部系统 scheme、危险 scheme、TLS 分类 |
| BrowserPrivacyTests | 3 | 普通/隐私 WebView 数据隔离、隐私关闭不入最近关闭 |
| BrowserSessionTests | 7 | M1 配置、UA 不伪造、探测脚本全 frame 注入、设置开关、通用会话 |
| BrowserTabManagerTests | 7 | 多标签创建/切换/关闭/事件转发、10 标签生命周期 |
| BookmarkStoreTests | 7 | 书签持久化、去重、删除、URL 匹配、批量删除 |
| DiagnosticsStoreTests | 8 | 容量、脱敏写入、严重级、导出 JSON/文本/临时文件 |
| GameSessionStateTests | 16 | 加载、PiP 开关、前后台、网络、停滞、崩溃、恢复、退出、三层验证 |
| HistoryStoreTests | 4 | 历史持久化、搜索、文件/空白跳过、上限/删除/清空 |
| LocalHTTPServerTests | 7 | 回环、MIME、Range、404、路径穿越、双端口、解析器 |
| LoginPopupIntegrationTests | 1 | target=_blank/window.open 转标签、关闭弹窗标签不刷新主页面 |
| MediaProbeIntegrationTests | 6 | 本地视频快照/事件、Canvas、跨域 iframe、控件禁用、UTF-8 文本 |
| MediaProbeTests | 14 | 快照/事件解码、origin 清洗、聚合分类、上限、PiP 原因映射、脚本资源 |
| PrivacyRedactorTests | 10 | URL/Cookie/Authorization/token/邮箱/手机/JWT/UUID/长密钥/元数据 |
| RecentlyClosedStoreTests | 3 | 最近关闭记录/跳过空白/恢复/清空 |
| SessionMonitorTests | 9 | 加载、媒体、前后台、网络、失败、恢复计数、诊断快照 |
| SessionPersistenceTests | 2 | T09：跨 BrowserSession 的 WebKit Cookie 持久化；T11：SwiftUI host 重建后同一 WebView/JS 状态 |
| SessionRecoveryTests | 12 | 无自动重载、用户确认、冷却、上限、窗口清理 |
| URLInputParserTests | 10 | 地址栏解析、域名/IP/IP:端口、HTTPS 补全、搜索回退、危险 scheme 拒绝 |
| BrowserFeatureTests | 6 | PiP 跨标签绑定/来源保护、书签文件夹排序、搜索引擎、10 标签生命周期、共享下载队列 |
| DownloadManagerTests | 13 | 文件名清洗、目标路径冲突编号、暂停/恢复/取消回退状态、分享与续传标记、新条目置顶 |
| AppCoordinatorStartPageTests | 6 | 起始页数据支撑：恢复最近关闭标签并路由到浏览器、无快照无操作、新建标签路由、最近关闭经协调器暴露 |
| WebPictureInPictureTests | 6 | 平台/配置/探测门控、enter/leave 状态、M4 不可行 |
| TabSessionStoreTests | 5 | 标签持久化：版本校验、去重、空白过滤、上限、清空 |
| BrowserTabPersistenceTests | 7 | 冷启动恢复、ID 稳定、恢复页仅激活时加载、隐私不落盘、批量关闭 |
| MediaSchedulingTests | 7 | 仅活动+PiP来源轮询、切后台全停、PiP全局状态、后台不停止 PiP |
| PiPSourceCloseTests | 5 | 关闭来源需确认、先停PiP后销毁、超时兜底、批量关闭、协调器释放 |
| TabThumbnailCacheTests | 4 | Caches PNG、过期、删除/清空、不写 UserDefaults |
| BrowserContainerTests | 2 | WebView 容器切换不重建/不重载、10 标签稳定实例 |
| BrowserPerformanceTests | 3 | 标签创建/切换/关闭耗时、10标签 footprint、历史写入 |
| AriunoUITests（XCUITest） | 4 | 起始页入口、新标签仍为首页、标签面板计数、地址栏导航到真实 WebView |
| **合计** | **201 + 4** | |

构建日志与测试日志：`build/test-final.log`、`build/release-final.log`（本地生成，不含凭证）。

## 2. T01–T12 验收矩阵

| 编号 | 测试 | 自动化/代码证据 | 当前状态 | 真机通过条件 |
|---|---|---|---|---|
| T01 | 普通网页视频进入 PiP | 真机 iPhone 15 Pro：页面内 PiP → 浮窗出现；后台 5 分钟保持；时间码 6.125→19.667（12 秒间隔）持续推进 | ✅ PASS（真机本地视频，2026-11-16） | 真机点击页面内 PiP 控件，浮窗出现，播放 5 分钟时间码/画面持续变化 |
| T02 | 官方云游戏登录 | 真机 iPhone 15 Pro：官方登录面板 → 用户自行登录 → 进入云游戏；无 WKWebView 拒绝提示 | ✅ PASS（真机，单设备/单次） | 真机通过官方网页完成登录并进入云游戏，无被拒绝的 WKWebView 检测 |
| T03 | 游戏实时画面 PiP | 真机游戏自动战斗中进入 PiP；切到 Settings 后浮窗仍显示实时战斗画面，t0→1min 战斗伤害/状态推进；约 15 分钟因服务器空闲断开 | ✅ PASS（单次约 5 分钟实时 PiP；长期会话见 T04/T05 FAIL） | 游戏画面非截图、时间码/动画持续、进入 PiP 后不立即断线 |
| T04 | 后台 1/5/15/30 分钟 | 真机第 1 次运行：1/5 分钟 PiP 保持、战斗推进；约 15 分钟游戏提示“连接中断/长时间未操作/错误码 -1022”，PiP 结束；30 分钟未达到 | ❌ **FAIL** | 每个时长记录 PiP、画面变化、返回后真实游戏状态；至少 30 分钟 3 次 |
| T05 | 自动战斗 | 真机第 1 次：自动战斗从进行中推进到胜利/结算；随后服务器空闲断开（-1022）；仅 1 次且会话未持续 | ❌ **FAIL**（1/3，且会话不持续） | 至少 3 次实际观察战斗推进且云会话持续；不能只看视频 |
| T06 | 网页不可 PiP | `PiPFailureReason` 映射单测；能力检测页显示具体原因；工具栏禁用按钮并显示原因 | ✅ PASS（模拟器/UI） | 真机无可用视频/不支持时同样显示原因，无虚假成功 |
| T07 | 网络断开恢复 | `RecoveryPolicy`/`WebContentRecovery` 单测：所有非用户触发都不自动重载；60 秒冷却、3 次上限 | ◐ PARTIAL | 真机断网/恢复：不无限重试，提示断线，手动恢复可继续或安全重登 |
| T08 | WebContent 崩溃 | 状态机 `processTerminated → failed`；浏览器不自动 reload；恢复提示 | ◐ PARTIAL | 真机触发 WebContent 崩溃：不崩溃/不死锁，提示需要恢复，用户确认后可恢复 |
| T09 | Cookie 保持 | 真机重装/重启后仍为已登录状态，直接显示“进入游戏”；`SessionPersistenceTests` 另验证跨 BrowserSession Cookie 持久化 | ✅ PASS（真机，App 升级/重启级别） | 重启 App 后官方登录状态按服务器策略保留；仅显式清除网站数据才退出 |
| T10 | 隐私与安全 | 脱敏单测、TLS 错误分类/拒绝弃用 TLS、无凭证日志、权限拒绝、隐私清单 | ✅ PASS（代码/自动化） | 真机复测无账号/密码/token 泄露；不忽略证书错误 |
| T11 | PiP 点击返回 | 真机本地视频：PiP 后切后台并返回，仍为同一页面/WebView，presentationMode=picture-in-picture；游戏内返回待 30 分钟结束；`SessionPersistenceTests` 验证 host 重建 | ◐ PARTIAL | 从 PiP 小窗返回：同一 WebView、无无故刷新、可继续操作 |
| T12 | 资源使用 | 前台 3 秒低频轮询 + 事件驱动；后台停止；无忙轮询 | ◐ PARTIAL | Instruments/真机长时间运行无内存线性增长、无持续高 CPU |

## 3. 真机矩阵（部分已填）

### 3.1 设备

| 设备 | 型号标识 | iOS | 角色 | 备注 |
|---|---|---|---|---|
| 当前主力 iPhone 15 Pro | iPhone16,1 | 27.2.1 | 主验证 | 2026-11-16；Wi-Fi（私有网络）+ 5G；VPN 已连接 |
| 较低主要版本设备 | | | 兼容性 | 至少一个较低主要版本 |
| iPad（可选） | | | 布局/弹窗 | 非任务硬性要求 |

### 3.2 场景矩阵

每个设备至少执行：

| 场景 | 预期 | 记录 |
|---|---|---|
| Wi-Fi 播放/登录 | 页面与媒体正常 | |
| 蜂窝网络播放/登录 | 受运营商/延迟影响时如实提示 | |
| 切后台 1/5/15/30 分钟 | PiP 与媒体状态按实际记录 | |
| 锁屏/息屏 | 记录 PiP/音频/返回状态 | |
| 来电/音频中断 | 记录是否恢复、是否重连 | |
| 耳机插入/拔出/蓝牙切换 | 音频路由与播放状态 | |
| 低电量模式 | 记录系统限制/暂停 | |
| 内存压力（打开多个 App） | WebContent 是否终止、恢复提示 | |
| 关闭 PiP 小窗 | 游戏会话保留，不刷新 | |
| 旋转/横竖屏 | 网页输入坐标、工具栏、安全区 | |
| 动态岛/刘海机型 | 工具栏不被遮挡、游戏可操作 | |
| 弱网/断网/恢复 | 不无限重试，提示，手动恢复 | |
| 起始页：最近访问 | 显示最近浏览的网页（隐私标签不计入），点击可打开 | |
| 起始页：最近关闭的标签页 | 显示最近关闭条目，“恢复关闭的标签页”可还原 | |
| 起始页：新建标签页/书签/历史/下载入口 | 四个快捷入口均可用 | |
| 下载：进度与暂停 | 下载中显示进度；暂停后状态为“已暂停” | |
| 下载：继续（断点续传） | 暂停后可继续并完成；服务器不支持续传时如实提示 | |
| 下载：分享 | 完成的文件可经系统分享面板分享 | |
| 下载：取消 | 取消后状态为“已取消” | |

## 4. 30 分钟场景记录（至少 3 次）

每次运行都必须有“游戏实际进度变化证据”，不能只看视频仍显示。

| 运行 | 日期/设备/iOS | 网络 | 开始进度指标 | 5 分钟 | 15 分钟 | 30 分钟 | PiP 仍显示 | 媒体时间码/动画变化 | 音频 | 返回后同 WebView | 返回后游戏真实进度 | 服务器提示 | 录屏/截图 | 结论 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| #1 | 2026-11-16 / iPhone 15 Pro / iOS 27.2.1 | Wi-Fi + 5G + VPN | 自动战斗进行中 | PiP 保持、战斗推进 | **断线**：连接中断/长时间未操作/错误码 -1022 | **锁屏、无 PiP**（15 分钟已断开） | 否 | 是（t0→5min） | 中断 | 是（同一页面，无重载） | 战斗从进行到胜利结算，随后会话被服务器中断 | “因为您长时间未操作游戏，已中断连接 错误码：-1022” | [真机报告](real-device-verification.md) / 脱敏截图 | **FAIL** |
| #2 | 未执行 | — | — | — | — | — | — | — | — | — | — | — | — | 因 T04/T05 已出现服务器空闲断开，按任务书不伪造成功；未重复规避 |
| #3 | 未执行 | — | — | — | — | — | — | — | — | — | — | — | — | 同上 |

### 4.1 判定细则

- **PiP 仍显示**：系统浮窗未消失。
- **媒体时间码/动画变化**：截图/录屏在 5/15/30 分钟节点可见不同时间码或场景变化；不能用同一帧。
- **返回后同 WebView**：无重新加载白屏、无重复登录页、无会话重建。
- **返回后游戏真实进度**：战斗波次、角色血量、任务进度、体力/关卡状态等有可量化变化。
- **服务器提示**：断线、超时、重连、会话结束等原文（脱敏）。
- 任何一项缺失 → 该次记为 FAIL/UNVERIFIED，不能作为挂机证据。

## 5. T05 自动战斗记录（至少 3 次）

| 运行 | 开始时间 | 战斗/波次/进度（开始） | 检查时间 | 战斗/波次/进度（检查） | 无输入下推进 | 云会话持续 | 是否自动下一轮（不要求） | 证据 | 结论 |
|---|---|---|---|---|---|---|---|---|---|
| #1 | | | | | | | | | |
| #2 | | | | | | | | | |
| #3 | | | | | | | | | |

说明：本项目不要求游戏自动开始下一轮战斗，也不制作自动点击脚本；只观察游戏原有自动战斗在无输入/后台时是否按服务器策略继续。

**结论：T04/T05 FAIL。** 服务器在约 15 分钟无输入后主动断开（-1022），这是云服务空闲策略；任务书明确禁止绕过。因此只能交付浏览器 + 诊断原型，不得宣称后台挂机。详见 [real-device-verification.md](real-device-verification.md) 与 [known-limitations.md](known-limitations.md)。

## 6. 会话/登录/重连专项

| 检查 | 方法 | 当前自动证据 | 真机结果 |
|---|---|---|---|
| SwiftUI 重建不丢会话 | 首页 ↔ 浏览器、旋转、PiP 开关、前后台 | 多标签架构 + `SessionPersistenceTests`（host 重建后 JS 标记仍存在） | |
| 不重复登录 | 返回前台、PiP 返回、关闭/打开工具栏 | 不 reload；`SessionPersistenceTests` 验证 WebKit Cookie 跨实例持久化；官方登录待真机 | |
| 不恶意重连/重复计费 | 断网恢复、崩溃、停滞 | `SessionRecoveryTests` 验证无自动 reload、冷却/上限 | |
| 退出会话保留登录 | 菜单“退出会话”后重进 | `endSession()` 只加载 about:blank，不清理网站数据 | |
| 清除网站数据退出登录 | 设置确认对话框 | 显式 `removeData(allWebsiteDataTypes)` | |
| PiP 关闭不结束游戏 | 关闭系统浮窗 | 状态机 `pipStopped → ready` | |

## 7. 失败/阻断处理

1. T02/T03/T05 未通过：只能交付浏览器与诊断原型；在 [known-limitations.md](known-limitations.md) 逐项解释失败原因。
2. 官方页面不兼容 WKWebView / 无媒体 / 媒体不可 PiP / 后台被挂起：在 UI 与文档标记 `不支持/待验证/无法后台维持`，不得伪造状态。
3. 任何自动重连造成的重复云游戏计费：立即记录并调整恢复策略，默认仍保持“仅用户确认”。
4. 测试证据含账号/令牌：立即删除，重新以脱敏方式采集。

## 8. 通过条件与签字

- 自动化：201/201 通过（当前）+ XCUITest 4/4 通过（模拟器真实点击）。
- 真机：T01/T02/T03/T09 PASS（T03 为单次约 5 分钟实时 PiP）；T04/T05 **FAIL**（15 分钟空闲断线 -1022）。T06–T08/T10–T12 部分待补。
- 30 分钟：第 1 次在 15 分钟失败；#2/#3 未执行。不得把 T04/T05 记为通过。
- 结论：交付范围降级为浏览器 + 诊断原型；后台挂机不可交付。
- 隐私：导出日志抽查无凭证；不忽略证书错误。
- 审核：完成 [app-review-risk.md](app-review-risk.md) 的发布前确认。

| 角色 | 姓名 | 日期 | 结论/签字 |
|---|---|---|---|
| 开发 | | | |
| QA | | | |
| 产品/合规 | | | |

当前签字状态：**未签字**（真机与账号验证缺失）。
