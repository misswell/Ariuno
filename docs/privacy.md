# 隐私说明（Ariuno）

本说明描述 Ariuno 本体的数据处理。登录、游戏与云服务数据由米哈游官方网页及其服务处理，适用其隐私政策；Ariuno 不接收账号密码，也不把数据发送到自建或第三方服务器。

## 1. 数据分类

| 数据 | 是否存储 | 说明 |
|---|---|---|
| 账号、密码、验证码 | **不存储、不读取** | 只在官方网页内输入；App 无对应输入框/API |
| 登录 Cookie、网站本地存储 | 由 WKWebView 默认持久化存储管理 | App 只读取域名级 Cookie 网站记录数（总数/米哈游相关数），不读取 Cookie 名称/值或 HttpOnly 内容 |
| 诊断事件 | 仅内存（默认 800 条） | 用户导出前脱敏；不自动落盘、不上传 |
| 用户设置 | `UserDefaults` | 工具栏/PiP/音频/日志开关等，不含凭证 |
| 导出文件 | 用户主动导出时写临时目录 | 分享结束删除；若用户另存，由用户保管 |
| 设备型号、iOS 版本 | 导出时生成 | 用于诊断；不含 UDID/序列号 |
| 网络接口类型 | 内存/诊断 | Wi-Fi/蜂窝/其他；不采集 IP/地址 |
| 位置、通讯录、照片、相机、麦克风 | **不采集** | 无相关权限请求；网页摄像头/麦克风请求被拒绝 |

## 2. 不收集/不上传

Ariuno 本体：

- 不包含分析 SDK、广告 SDK、崩溃上报 SDK 或第三方追踪；
- 不向自建服务器、第三方云转码或非官方页面发送数据；
- 不自动上传诊断日志；
- 不读取剪贴板（用户主动“复制 JSON”除外，方向是写入剪贴板）；
- 不使用 IDFA/IDFV 做追踪，不进行跨 App 追踪；
- 不读写通讯录、照片、位置、健康等数据。

官方网页在 WebView 内可能自行设置 Cookie、localStorage、IndexedDB、缓存并连接米哈游服务；这些行为受官方网页与米哈游隐私政策约束。Ariuno 不拦截/导出这些内容。

## 3. 诊断脱敏

[`PrivacyRedactor`](../CloudFloat/Diagnostics/PrivacyRedactor.swift) 在写入内存日志和导出前：

- 将 URL 归约为 `scheme://host[:port]`，丢弃 path、query、fragment（避免一次性登录票据、token）；
- 替换 `Authorization`/`Proxy-Authorization`/`Cookie`/`Set-Cookie` 整行；
- 替换 `token/stoken/ltoken/cookie_token/login_ticket/password/account_id/uid/mid/...` 键值对（保留键名，值替换）；
- 替换 Bearer、JWT、邮箱、手机号、UUID、长 base64/hex 字面量；
- metadata 的敏感键整个值替换，限制条目数与长度；
- 页面探测上报的 origin 由原生再次清洗为 `scheme://host[:port]`；不采集视频 `currentSrc`。

脱敏是纵深防御，不是“允许记录秘密”。代码调用点仍禁止读取/转发 Cookie 值、token 或完整带凭证 URL。

## 4. 权限与后台能力

- 相机/麦克风：不声明用途描述；网页采集请求由 `WKUIDelegate` 拒绝。
- 位置/VoIP/后台处理：不声明、不使用。
- 本地网络：Debug 开发者测试页使用回环 `127.0.0.1` 服务器；Info.plist 的本地网络说明仅用于该开发工具。正式游戏不依赖本地服务。
- 后台音频：只声明 `audio`，只在真实媒体播放或 PiP 可见时配置；不使用静音音频保活。见 [background-audio.md](background-audio.md)。

## 5. 保留与删除

- 诊断：内存中，App 退出即丢失；用户可在“诊断”中清除。
- 设置：保留在 UserDefaults，直到用户重置/删除 App。
- 网站数据/Cookie：由 WKWebView 持久化；只有用户在“设置 → 清除网站数据”明确确认后，App 才调用 `WKWebsiteDataStore` 删除全部网站数据类型（Cookie、本地存储、IndexedDB、缓存等），并退出当前会话/PiP。
- 导出文件：分享结束后 App 删除临时文件；用户另存/转发的副本由用户管理。

## 6. 安全措施

- HTTPS 导航；HTTP 仅允许回环测试页；非官方主框架链接先确认再交给系统浏览器。
- 服务器信任 challenge 使用系统默认校验；无效证书导致导航失败并提示；拒绝已弃用 TLS；不忽略证书错误。
- 阻止 `itms-services`、`javascript:`、`data:`、`blob:`、`file:`（测试目录外）和未知自定义 scheme。
- 登录弹窗使用隔离 content controller；不执行网页发来的 native 指令；摄像头/麦克风默认拒绝。
- 不提供账号密码存储、自动登录或 token 导出。
- 本地测试服务器只绑定回环、只读 TestPages、无目录列表、路径穿越拒绝、Debug/开发者工具专用。

## 7. App Store 隐私标签建议

基于当前实现（发布方仍需按最终版本复核）：

- **Tracking**：No。
- **Data Linked to You**：无（App 本体不收集）。
- **Data Not Linked to You**：无自动收集。用户主动导出的诊断文件由用户控制，App 不上传。
- **Third-Party Advertising**：No。
- **Privacy Manifest**：已包含 `PrivacyInfo.xcprivacy`，仅声明 `UserDefaults` 访问原因 `CA92.1`；无追踪域。
- 官方网页在 WebView 内的数据实践可能需要在 App 隐私说明中链接米哈游隐私政策，并明确“网页内容由第三方提供”。

## 8. 发布方需补充

- 隐私政策公开 URL、支持联系方式、数据处理者信息；
- 若未来加入账号、云同步、崩溃上报或分析 SDK，必须更新本说明、隐私清单与 App Store 标签，并重新评估授权/同意；
- 真机测试证据必须脱敏（账号、手机号、验证码、UID、Cookie、token URL）。

## 9. 联系

本仓库不包含运营主体信息。发布前由发布方在隐私政策中提供可联系的数据保护/支持渠道。

> 本说明不是法律意见；上架前应由发布方完成隐私政策与当地法律/App Store 要求的复核。
