# 后台音频能力使用说明

## 1. 声明了什么

`Info.plist`：

```xml
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
</array>
```

未声明 `location`、`voip`、`fetch`、`processing`、`remote-notification` 等其他后台模式。没有播放静音音频，没有后台截图/录屏，没有伪视频通话。

## 2. 为什么需要

云游戏与网页视频在真实播放时需要音频；当系统 PiP 浮窗可见或真实媒体仍在播放时，保持 `.playback` 音频会话可让音频在后台/PiP 场景下按系统策略继续。这是 `audio` 后台模式的正当用途（真实媒体播放），不是为了保活 JS/WebSocket。

## 3. 代码行为

[`AudioSessionManager`](../CloudFloat/Session/AudioSessionManager.swift)：

- 仅在以下条件调用 `AVAudioSession.setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay])` 和 `setActive(true)`：
  - 真实媒体正在播放，且 App 在前台；或
  - PiP 浮窗可见（`pipVisible`）。
- 后台且没有 PiP、没有真实媒体时，不保持音频会话；
- 真实播放停止后延迟 3 秒 `setActive(false, options: .notifyOthersOnDeactivation)`；
- 不创建 `AVAudioPlayer`/静音音轨/无声音频循环；
- 错误只写入诊断（去重），不静默忽略。
- 设置中可关闭“后台音频（仅真实媒体）”；关闭后停止配置音频会话。

## 4. 与 PiP 的关系

- HTML5 PiP 由 WebKit 进入；App 不通过 `AVPictureInPictureController` 伪造视频通话 PiP。
- 音频会话不负责“让 PiP 出现”，只负责真实媒体播放的音频类别；PiP 是否出现由网页视频能力/用户点击/系统决定。
- 如果 PiP 不出现，App 不会用音频后台模式假装成功；诊断与 UI 会显示原因。

## 5. App Review 2.5.4 注意事项

Apple《App Store Review Guidelines》2.5.4 要求后台模式只用于其预期用途（音频、位置、VoIP 等），并限制滥用。提交时需要：

1. 在审核备注中说明：`audio` 仅用于官方网页中真实云游戏/视频的音频与 PiP，不播放静音音频、不做保活；
2. 提供可复现步骤：打开官方页面/本地测试视频 → 播放 → 进入 PiP → 切后台，音频按系统策略继续；
3. 说明测试账号（如审核需要）由发布方在授权范围内提供，仓库不包含；
4. 若审核认为该能力与 App 主要功能不符，或 PiP 实际不可用，**应移除 `UIBackgroundModes: audio` 或关闭音频设置**，而不是用其他后台模式替代；
5. 不使用“视频通话”类 PiP 权限/私有 API 规避审核。

## 6. 测试步骤（真机）

1. 真机安装 Debug/Release 构建，打开本地 `native-video.html`（或官方视频页），确认有真实音频。
2. 播放并进入 PiP；切到其他 App；确认音频/PiP 按系统策略继续（不是静音音频）。
3. 暂停/退出视频；等待 >3 秒；确认音频会话释放（其他 App 音频可恢复）。
4. 关闭设置中的“后台音频”；重复步骤 2，记录差异。
5. 后台 1/5/15/30 分钟记录：音频、PiP、返回后会话；同时记录服务器端游戏进度。
6. 在 Xcode/Console 检查无静音音频、无异常 AVAudioSession 错误循环。

## 7. 风险与回退

| 风险 | 处理 |
|---|---|
| App Review 认为后台音频滥用 | 审核备注说明真实媒体用途；必要时移除 audio 后台模式/默认关闭设置 |
| 音频会话与其他 App 冲突 | 只在真实媒体/PiP 时激活，停止后 deactivate + notify |
| WebKit 自行管理音频会话导致冲突 | 捕获错误并诊断；不要让错误阻塞页面/PiP |
| 用户不希望后台音频 | 设置可关闭 |
| 把音频当作保活手段 | 明确禁止；代码不播放静音音频，不依赖音频维持 JS/会话 |

## 8. 结论

`audio` 后台模式只有在真实媒体/PiP 场景下才有正当性；它不是“后台挂机”的证明或保活机制。若 T02/T03/T05/30 分钟证据未完成，不应在宣传中使用“后台持续”表述，也不应为了保活扩大后台模式。
