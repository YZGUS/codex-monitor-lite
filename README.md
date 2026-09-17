# Codex Monitor Lite

一个原生、只读、轻量的 macOS 菜单栏工具，用于集中查看最近 24 小时内的本机 Codex 任务状态。

界面采用紧凑的毛玻璃面板，重点呈现正在运行、等待用户处理和等待查看的任务。当前版本完全在本机工作，不上传 Prompt、源码或终端输出。

## 功能

- **最近 24 小时**：只读取最后活动时间位于最近 24 小时内的会话，旧会话不会继续解析。
- **四类状态**：全部、运行中、需要你、待查看。
- **高密度菜单栏界面**：固定 320 pt 宽度，长标题、路径、分支和模型自动截断。
- **任务上下文**：显示项目、Git 分支、模型、持续时间和当前动作。
- **快速返回 Codex**：从任务卡片直接打开对应会话。
- **本地已读状态**：打开已完成任务后，会在本机记录为已查看。
- **只读与无网络**：通过本机 Codex App Server 和 rollout 生命周期事件获取状态；当前 `EventPublisher` 是空实现。
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
3. 点击任务卡片右下角的打开按钮返回 Codex。
4. 点击面板外或按 `Esc` 收起面板；点击右上角电源按钮退出应用。

### 状态含义

| 状态 | 含义 |
| --- | --- |
| 运行中 | App Server 或本地生命周期事件明确显示任务仍在执行 |
| 需要你 | 检测到授权请求或用户输入请求 |
| 待查看 | 任务已完成，但尚未从本工具打开查看 |
| 已查看 | 已完成任务已被打开过，仍可在“全部”中看到 |

## 隐私与数据边界

- Codex 读取通过本机 `stdio` 完成，当前版本不会发起网络请求。
- Prompt、源码、终端输出、令牌和绝对路径不会进入可发布的 `StandardEvent`。
- 标题与本地路径只保存在 `LocalTaskContext` 中，用于当前 Mac 的界面展示。
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

EventPublisher ── NoopEventPublisher（当前无网络）
```

- `SourceAdapter`：隔离不同消息来源。
- `StandardEvent`：与 Codex 解耦的版本化事件；时间使用带毫秒的 RFC 3339 UTC，持续时间使用整数毫秒。
- `LocalTaskContext`：保存只适合本机展示、禁止外发的上下文。
- `EventPublisher`：未来向云服务推送安全事件的接口；当前为空实现。

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
```

这些夹具使用独立临时存储，不会污染正式任务状态。

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
```

## 当前限制

- Codex Desktop 的独立 App Server 无法提供所有进程内实时状态，应用会保守地组合 App Server 数据与本地生命周期证据。
- 仓库不包含已签名或公证的发行包；本地 Release 产物不会提交到 Git。
- 云服务、Android 客户端和消息推送尚未实现，相关边界见 [`Docs/AndroidMessageCenter.md`](Docs/AndroidMessageCenter.md)。
