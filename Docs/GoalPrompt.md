# Goal 提示词

在 `/Users/cengyi/Desktop/tools/codex-monitor-lite` 开发一个完全独立的原生 macOS 菜单栏应用。首版只读监控本机 Codex 任务，提供“运行中 / 需要你 / 待查看”筛选、紧凑卡片、持续时间、本地持久化和打开原任务；通过 `SourceAdapter` 保留其他消息来源扩展能力，通过无网络实现的 `EventPublisher` 预留未来云端推送接口。统一事件使用版本化结构，时间传输为 RFC 3339 UTC 毫秒、持续时间为整数毫秒，禁止外发 Prompt、源码、终端输出和绝对路径。

UI 参考用户提供的图片，采用 macOS 原生毛玻璃、极简、高密度、清晰状态层级；面板固定宽 320 pt，一屏最多四张卡片，大量任务仅列表滚动。支持 Pin 为常驻浮动面板，并由用户拖动选择和保存位置。只读取并显示最后活动时间在最近 24 小时内的 Codex 对话。完成单元测试、真实 Codex App Server 只读集成测试，并实际运行 `.app` 验收 `normal / empty / loading / error / long / many` 六种视觉状态。

Android 与云服务保持为后续独立项目：本阶段只交付多来源消息中心的页面、事件流、隐私和扩展边界设计，不实现网络、FCM 或 Android 代码。
