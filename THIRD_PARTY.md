# 第三方依赖与开源参考说明

## 1. 运行时依赖

Ariuno **不包含任何第三方运行时依赖**：

- 无 Swift Package（无 `Package.swift`、无 `Package.resolved`）；
- 无 CocoaPods / Carthage；
- 无 Chromium、Gecko、WebKit 以外的浏览器引擎；
- 无独立 JavaScript 引擎；
- 无 React/Flutter/Electron 等跨端运行时；
- 无第三方 UI 组件库；
- Release 包内无 `.framework` 或 `.dylib`。

使用的全部能力来自 iOS 系统框架：

| 框架 | 用途 |
|---|---|
| SwiftUI | 界面与视图状态 |
| UIKit | `UIViewRepresentable`、分享面板、文件选择 |
| WebKit | `WKWebView`、导航/下载/上传、网站数据 |
| AVKit / AVFoundation | 系统 PiP 状态、`AVAudioSession` |
| Network | `NWPathMonitor` 网络状态 |
| Combine | 会话对象变更转发 |

## 2. DuckDuckGo BareBonesBrowser 参考说明

架构设计参考了 [duckduckgo/BareBonesBrowser](https://github.com/duckduckgo/BareBonesBrowser)
（Apache License 2.0）的极简 `WKWebView` + SwiftUI 封装思路。

实际情况：

- Ariuno **没有复制或修改** BareBonesBrowserKit 的源代码；
- 没有复制其 Logo、品牌或产品资源；
- 相关 Swift 文件（`BrowserSession.swift`、`CloudWebView.swift`、`BrowserTabManager.swift` 等）
  均为本项目自行编写，版权归 Ariuno 项目所有；
- 因此仓库不附带 Apache 2.0 许可的衍生代码，也不冒充 DuckDuckGo 产品。

如果未来引入或复制该项目的源代码，必须：

1. 在仓库保留 Apache License 2.0 全文；
2. 保留原始版权与许可声明；
3. 不复制 DuckDuckGo 品牌资源；
4. 在本文档登记来源文件与修改内容。

## 3. 测试与开发工具

- XcodeGen：仅用于从 `project.yml` 生成 Xcode 工程，不进入 App 包。
- 本地回环 HTTP 服务器（`LocalHTTPServer.swift`）为本项目自行实现，仅 Debug 构建启用。

## 4. 品牌

Ariuno 为独立产品名称。仓库不使用《崩坏：星穹铁道》、米哈游（miHoYo）、HoYoverse 的 Logo 或官方素材，
也不声称与上述公司存在合作或授权关系。
