# Codex Monitor Lite

一个原生、只读、轻量的 macOS 菜单栏工具，用于集中查看最近 24 小时内的本机 Codex 任务状态，并可选择在同一局域网内同步到 Android 手机。

界面采用紧凑的毛玻璃面板，重点呈现正在运行、等待用户处理和等待查看的任务。公网传输仍为空实现；局域网功能默认关闭，只发送经过裁剪的只读任务快照。

## 功能

- **最近 24 小时**：只读取最后活动时间位于最近 24 小时内的会话，旧会话不会继续解析。
- **三类状态**：运行中、需要你、待查看；已查看任务不再占用界面。
- **高密度菜单栏界面**：固定 320 pt 宽度，三行卡片，一屏最多四张，更多任务在列表内滚动。
- **固定到桌面**：点击 Pin 切换为常驻浮动面板，拖动顶部空白区自由摆放，位置会自动保存。
- **最少必要上下文**：卡片只显示标题、当前状态、项目、相对时间和持续时间。
- **整卡返回 Codex**：点击卡片任意位置打开对应会话。
- **本地已读状态**：打开已完成任务后，会在本机记录为已查看。
- **可选局域网查看**：Mac 主动开启后，Android 使用 Bonjour 自动发现并通过连接码只读连接；不需要公网服务器。
- **默认本地工作**：通过本机 Codex App Server 和 rollout 生命周期事件获取状态；当前公网 `EventPublisher` 仍为空实现。
- **可扩展协议**：`SourceAdapter` 支持未来接入其他消息来源，`StandardEvent` 为云端和移动端预留统一事件格式。

## 环境要求

- macOS 14 或更高版本
- Xcode，以及可用的 macOS 14+ SDK
- 本机已安装 Codex Desktop，或可在命令行中执行 `codex app-server`

应用会依次查找：

1. `CODEX_EXECUTABLE` 指定的路径
2. ChatGPT / Codex 应用包内的 Codex 可执行文件
3. Homebrew 或系统 `PATH` 中的 `codex`

## 快速开始

推荐从 [GitHub Releases](https://github.com/YZGUS/codex-monitor-lite/releases/latest) 下载最新的通用 macOS 压缩包。当前包使用临时签名、尚未经过 Apple 公证；首次运行如被系统拦截，请在 Finder 中右键应用并选择“打开”。

也可以从源码构建：

```bash
git clone https://github.com/YZGUS/codex-monitor-lite.git
cd codex-monitor-lite

xcodebuild \
  -project CodexMonitorLite.xcodeproj \
  -scheme CodexMonitorLite \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$PWD/.build/DerivedData" \
  CODE_SIGNING_ALLOWED=NO \
  build

open -na "$PWD/.build/DerivedData/Build/Products/Debug/CodexMonitorLite.app"
```

也可以直接用 Xcode 打开 `CodexMonitorLite.xcodeproj`，选择 `CodexMonitorLite` scheme 后运行。

## 使用方式

1. 启动应用后，点击 macOS 菜单栏中的 Codex Monitor Lite 图标。
2. 使用顶部筛选器查看运行中、需要你或待查看的任务。
3. 点击任务卡片任意位置返回 Codex。
4. 点击 Pin 将面板固定到桌面；固定后拖动顶部空白区选择位置，再次点击 Pin 恢复菜单栏弹窗。
5. 未固定时，点击面板外或按 `Esc` 收起面板；点击右上角电源按钮退出应用。

## Android 局域网版

第一版 Android App 只有一个只读页面，不需要注册账户：

1. 确保 Mac 和 Android 手机位于同一可信 Wi-Fi。
2. 在 Mac 面板点击手机图标，开启“局域网共享”。
3. 在 Android App 输入 Mac 显示的连接码。
4. Android 前台持续显示三类任务；退到后台即断开。

从源码构建需要 JDK 17+ 与 Android SDK 36：

```bash
cd android
./gradlew :app:assembleDebug
```

APK 输出位于 `android/app/build/outputs/apk/debug/`。当前仓库未加入 Android Release 签名或商店发布流水线。

### 状态含义

| 状态 | 含义 |
| --- | --- |
| 运行中 | App Server 或本地生命周期事件明确显示任务仍在执行 |
| 需要你 | 检测到授权请求或用户输入请求 |
| 待查看 | 任务已完成，但尚未从本工具打开查看 |
| 已查看 | 已完成任务打开后从三类列表中隐藏，避免占用关注空间 |

## 隐私与数据边界

- Codex 读取通过本机 `stdio` 完成；只有用户主动开启时才启动局域网服务。
- Prompt、源码、终端输出、令牌和绝对路径不会进入可发布的 `StandardEvent`。
- 局域网快照只发送标题、项目名、状态、时间和持续时间；不会发送 Prompt、摘要、源码、终端输出、绝对路径、分支、模型、令牌或深链。
- v1 的局域网 TCP 没有 TLS，只应在可信 Wi-Fi 使用；连接码可以在 Mac 端随时更换。
- 超过 24 小时的会话会从任务快照移除，也不会读取其 rollout 详情。
- 无法确认的状态不会被猜测成“需要你”；本地非权威活动证据最多保留 24 小时。

## 架构

```text
Codex App Server + local rollout events
                  │
                  ▼
             SourceAdapter
                  │
          StandardEvent + LocalTaskContext
                  │
                  ▼
        Event reducer + JSONTaskStore
                  │
                  ▼
          SwiftUI menu bar interface
                  │
         safe read-only snapshot
                  │ Bonjour + TCP（opt-in）
                  ▼
        Android foreground viewer

EventPublisher ── NoopEventPublisher（当前无网络）
```

- `SourceAdapter`：隔离不同消息来源。
- `StandardEvent`：与 Codex 解耦的版本化事件；时间使用带毫秒的 RFC 3339 UTC，持续时间使用整数毫秒。
- `LocalTaskContext`：保存只适合本机展示、禁止外发的上下文。
- `EventPublisher`：未来向云服务推送安全事件的接口；当前为空实现。
- `LANTaskSnapshot`：与本地私有上下文分离的局域网最小字段快照，协议见 [`Docs/LANProtocol.md`](Docs/LANProtocol.md)。

## 测试

运行全部单元测试：

```bash
xcodebuild \
  -project CodexMonitorLite.xcodeproj \
  -scheme CodexMonitorLite \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$PWD/.build/DerivedData" \
  CODE_SIGNING_ALLOWED=NO \
  test
```

真实本机 Codex 集成测试默认跳过。显式运行只读集成测试：

```bash
xcodebuild \
  -project CodexMonitorLite.xcodeproj \
  -scheme CodexMonitorLiteLive \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$PWD/.build/DerivedData" \
  -only-testing:CodexMonitorLiteTests/CodexAppServerLiveTests \
  CODE_SIGNING_ALLOWED=NO \
  test
```

### UI 验收夹具

```bash
APP_PATH="$PWD/.build/DerivedData/Build/Products/Debug/CodexMonitorLite.app"

open -na "$APP_PATH" --args --fixture normal --show-popover
open -na "$APP_PATH" --args --fixture empty --show-popover
open -na "$APP_PATH" --args --fixture loading --show-popover
open -na "$APP_PATH" --args --fixture error --show-popover
open -na "$APP_PATH" --args --fixture long --show-popover
open -na "$APP_PATH" --args --fixture many --show-popover
open -na "$APP_PATH" --args --fixture many --start-pinned
```

这些夹具使用独立临时存储，不会污染正式任务状态。

## 发布

推送 `v*` 标签，或在 GitHub Actions 中手动运行 `Release macOS`，流水线会执行测试、构建 arm64/x86_64 通用应用、临时签名并发布 ZIP 与 SHA-256 校验文件。正式分发前仍需补充 Apple Developer ID 签名与公证。

## 项目结构

```text
CodexMonitorLite/
├── App/          # 应用生命周期与视图模型
├── Core/         # 事件模型、归并和时间格式
├── Persistence/  # 本地 JSON 状态存储
├── Sources/      # Codex 与测试数据适配器
└── UI/           # SwiftUI 界面和原生毛玻璃

CodexMonitorLiteTests/  # 单元测试、只读集成测试和夹具
Docs/                   # UI 验收、需求提示词和 Android/云端设计边界
android/                # 原生 Android 局域网只读客户端
```

## 当前限制

- Codex Desktop 的独立 App Server 无法提供所有进程内实时状态，应用会保守地组合 App Server 数据与本地生命周期证据。
- GitHub Release 提供临时签名但未公证的通用 macOS 包；当前不具备无警告安装体验。
- Android v1 仅支持前台、同一可信 Wi-Fi 和只读查看；不支持公网、系统推送或远程操作。
- 公网云服务、FCM 和多来源消息中心尚未实现，边界见 [`Docs/AndroidMessageCenter.md`](Docs/AndroidMessageCenter.md)。
