# Ariuno：创建 App Store 记录并推送 TestFlight

本机已配置好 App Store Connect API 密钥和分发证书。以下命令不需要 App 专用密码，
也不需要重复询问凭据。**`.p8`、证书私钥、Apple ID 密码不得打印、提交或外发。**

## 0. 当前状态（2026-11-17）

| 项目 | 状态 |
|---|---|
| App Store Connect API | `asc` 3.1.2，默认 profile `rork-admin`，Admin key `5KDZSQND5Q` |
| Team ID | `U8U443D7ZL`（Guofeng Liu） |
| 显式 App ID | 已创建：`com.misswell.Ariuno`，资源 ID `PJQF7UQ8T2` |
| App Store 描述文件 | 已创建并安装：`Ariuno AppStore`（ID `U3V2UYVTYQ`，有效期至 2027-09-06） |
| 分发证书 | `Apple Distribution: Guofeng Liu (U8U443D7ZL)`，证书资源 ID `J4Z29X3RMS` |
| App Store Connect App 记录 | **尚未创建**（`asc apps list --bundle-id com.misswell.Ariuno` 为空） |
| Apple 网页会话 | 未登录（`asc web auth status` → `authenticated:false`） |

## 1. 创建 App Store Connect App 记录

Apple 的公开 API **不支持创建 App 记录**；`asc web apps create` 需要 Apple 网页登录
（Apple ID + 密码 + 2FA）。密码只能由账号持有人输入，Agent 不读取、不代填。

### 方式 A：网页创建（推荐，最少步骤）

打开 <https://appstoreconnect.apple.com> → 我的 App → `+` → 新建 App：

| 字段 | 值 |
|---|---|
| 平台 | iOS |
| 名称 | `Ariuno` |
| 主要语言 | 简体中文 |
| Bundle ID | `com.misswell.Ariuno`（已注册，下拉可选） |
| SKU | `ARIUNO-IOS-001` |
| 用户访问权限 | 完全访问 |

创建后记下 App ID（10 位数字），后续上传会用到。

### 方式 B：命令行创建（需要先登录网页会话）

在**你自己的终端**执行并输入密码/2FA（不要在聊天中发送密码）：

```bash
asc web auth login --apple-id "<你的 Apple ID>" --public-provider-id U8U443D7ZL
asc web auth status                     # 期望 authenticated:true

asc web apps create \
  --name "Ariuno" \
  --bundle-id "com.misswell.Ariuno" \
  --sku "ARIUNO-IOS-001" \
  --primary-locale "zh-Hans" \
  --platform IOS \
  --version "0.1.0"
```

如果名称已被占用，`--auto-rename`（默认开启）会加后缀；需要精确名称时先在网页确认。
当前 App Store 搜索未发现同名 `Ariuno`。

## 2. 上传前准备

1. **递增 build 号**（每次上传都要新 build；首次可用 1）：
   ```bash
   # project.yml
   CURRENT_PROJECT_VERSION: "2"
   xcodegen generate
   ```
   或 `agvtool new-version -all 2`。版本号 `MARKETING_VERSION` 当前为 `0.1.0`。
2. 确认 `Info.plist` 含：
   ```xml
   <key>ITSAppUsesNonExemptEncryption</key><false/>
   ```
   已有；缺失会导致 TestFlight “Missing Compliance”。
3. 本仓库提供手动签名导出配置：`scripts/ExportOptions-appstore.plist`
   （profile `Ariuno AppStore`、证书 `Apple Distribution: Guofeng Liu`）。

## 3. Archive + 导出上传

```bash
cd /Users/guofeng/Code/solo/CloudFloat

xcodebuild -project Ariuno.xcodeproj \
  -scheme Ariuno \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/Ariuno-TF-2.xcarchive \
  -derivedDataPath build/DeviceDerivedData \
  DEVELOPMENT_TEAM=U8U443D7ZL \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="Apple Distribution: Guofeng Liu (U8U443D7ZL)" \
  PROVISIONING_PROFILE_SPECIFIER="Ariuno AppStore" \
  -allowProvisioningUpdates archive

~/.appstoreconnect/upload-testflight.sh \
  build/Ariuno-TF-2.xcarchive \
  scripts/ExportOptions-appstore.plist
```

成功标志（必须同时出现）：

```text
Upload succeeded
** EXPORT SUCCEEDED **
```

> 注意：不要只传归档路径。本项目使用手动 App Store 描述文件；必须把
> `scripts/ExportOptions-appstore.plist` 作为第二个参数，否则可能走自动/云端签名并在
> `IDEDistributionAnalyzeVersionStep` 卡住。

## 4. 等待处理并设置合规

```bash
# 查 App ID
asc apps list --bundle-id com.misswell.Ariuno --output table

# 等待构建处理完成（把 APP_ID 换成上一步的 10 位数字）
asc builds wait --app APP_ID --build-number 2 --platform IOS

# 显式设置导出合规（Info.plist 已声明，但 ASC 构建属性仍建议确认）
asc builds update --app APP_ID --latest --platform IOS --uses-non-exempt-encryption=false
```

`processingState` 从 `PROCESSING` 变为 `VALID` 后，构建才可用于 TestFlight。

## 5. TestFlight 分发

- **内部测试组**默认 `hasAccessToAllBuilds=true`：构建 `VALID` 后，内部测试者自动可见，
  不需要手动把 build 加到内部组（API 会对内部组返回 422，这是正常行为）。
- 外部测试者/公开链接需要创建组并显式分配 build，且首次需要 Beta App Review。

```bash
# 查看组
asc testflight groups list --app APP_ID --output table

# 如无内部组，可创建一个（按需）
asc testflight groups create --app APP_ID --name "Internal" --internal

# 外部组才需要：
# asc builds add-groups --build-id BUILD_ID --groups GROUP_ID
```

在 App Store Connect → TestFlight 中添加测试者邮箱即可开始内测。

## 6. 常见问题

| 现象 | 原因/处理 |
|---|---|
| `Error Downloading App Information` | App Store Connect 还没有对应 bundle ID 的 App 记录；先做 §1 |
| `Cloud signing permission error` | API 密钥不能做 Xcode 云端签名；使用本仓库的手动 plist 与已安装描述文件 |
| TestFlight 显示 Missing Compliance | build 的 `usesNonExemptEncryption` 为 null；执行 §4 的 `builds update` |
| 上传成功但 TestFlight 看不到 | 处理中（`PROCESSING`）或没有测试组；等 `VALID` 并检查内部测试组 |
| 重复 build 号上传被拒 | 递增 `CURRENT_PROJECT_VERSION` 后重新 archive |
| 描述文件过期/失效 | `asc profiles create` 重新生成，下载到 `~/Library/Developer/Xcode/UserData/Provisioning Profiles/` |

## 7. 与 Codex 规则的关系

`~/.codex/AGENTS.md` 规定 TestFlight/App Store 上传由 `luna_worker`（`gpt-6-luna`）执行。
当前 ZCode 会话没有配置该 worker/model；本文件只提供可复现流程与已完成的准备步骤，
不把“已上传”当作已完成，除非真实出现 `Upload succeeded`。
