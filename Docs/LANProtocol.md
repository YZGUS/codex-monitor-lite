# 局域网只读协议 v1

第一版只解决一个问题：Android 手机在与 Mac 相同的可信 Wi-Fi 中，前台查看最近 24 小时的任务状态。协议不经过公网，不支持远程操作。

## 发现与连接

- Mac 仅在用户打开“局域网共享”后启动 TCP 服务。
- Bonjour 服务类型：`_codexmonitor._tcp`。
- Android 使用系统 NSD 自动发现，不要求用户输入 IP 或端口。
- 每次连接先发送一行 UTF-8 JSON，换行符为 `\n`：

```json
{"type":"authenticate","pairingCode":"XXXXX-XXXXX"}
```

连接码去掉空格和连字符后比较，忽略大小写。验证失败时 Mac 立即断开连接。用户可在 Mac 端生成新连接码，旧连接随服务重启失效。

## 快照

验证成功后，Mac 立即发送一行快照；任务发生变化时继续在同一连接发送新快照。每条消息都是一行完整 JSON，不跨行。

```json
{
  "type": "snapshot",
  "schemaVersion": 1,
  "revision": "UUID",
  "generatedAt": "2026-09-18T00:00:00.000Z",
  "tasks": [
    {
      "id": "task-id",
      "source": "codex",
      "title": "任务标题",
      "project": "项目名",
      "status": "running",
      "lastActivityAt": "2026-09-18T00:00:00.000Z",
      "durationMs": 120000
    }
  ]
}
```

- `status` 仅为 `running`、`needsAttention`、`awaitingReview`；非活跃任务不会发送。
- 时间使用 RFC 3339 UTC 毫秒，持续时间使用整数毫秒。
- 快照只包含标题、项目名和状态元数据，不包含 Prompt、摘要、源码、终端输出、绝对路径、Git 分支、模型、令牌或 Codex 深链。
- Android v1 只消费 `schemaVersion = 1`，不向 Mac 回传任务操作。

## 安全边界

该协议是可信局域网内的轻量方案，不是互联网安全通道：

- 连接码用于阻止同一网络中的误连接，但当前 TCP 内容没有 TLS 加密。
- 只应在家庭或可信办公 Wi-Fi 使用；不要在酒店、机场等公共网络开启。
- 局域网共享默认关闭；Android 退到后台后主动断开。
- 公网访问、账户、FCM、远程审批和远程回复不属于 v1。
