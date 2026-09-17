# UI 验收基线

视觉基准：`/var/folders/wv/c7pqj5994kjb1h7df38g3lxr0000gn/T/codex-clipboard-1f1c503e-b484-471d-af48-9f463fbe1c2c.png`。

- 面板固定宽 320 pt、普通状态最大高 590 pt；错误横幅出现时最多 634 pt。屏幕较矮时高度自动收缩，只有中间任务列表滚动。
- Header、筛选区、Footer 固定；卡片高 104 pt、间距 6 pt，一屏最多完整显示 4 张。
- 筛选区只保留“运行中 / 需要你 / 待查看”，默认进入“运行中”，不再显示“全部”。
- Pin 后变为跨桌面的常驻浮动面板；顶部空白区可拖动，取消 Pin 后恢复菜单栏弹窗，用户位置跨重启保存。
- 右上角电源按钮单击即退出应用；关闭面板使用点击外部或 `Esc`，不再使用齿轮二级菜单。
- 外层使用真实 `NSVisualEffectView` 毛玻璃；卡片只增加轻色层、细描边和 hover 反馈。
- 状态同时使用文字和颜色：运行绿、需要你琥珀、待查看蓝、非活跃灰；红色仅用于连接或明确错误。
- 标题、路径、分支、模型和动作全部单行截断并提供 tooltip；长文本不得改变卡片高度或挤压状态胶囊。
- 需要实际运行 `.app`，分别验证 `normal / empty / loading / error / long / many` 场景。成功编译和 SwiftUI Preview 不算视觉验收。
- 使用 `--fixture many --start-pinned` 验证固定态、四卡片视口、拖动和位置恢复。
- Retina 截图检查：毛玻璃、对齐、层级、卡片密度、无横向滚动、Footer 不漂移。
- 辅助功能检查：Reduce Transparency、键盘焦点、VoiceOver label、状态不只依赖颜色。

## 实际验收（2026-09-17）

在 Apple Silicon Retina Mac 上运行构建产物逐项检查：

| 场景 | 结果 |
| --- | --- |
| `normal` | 320 pt 窄面板、三类筛选、Pin 与固定 Footer 正常 |
| `empty` | 高度自动收紧，空态居中，无多余大面积留白 |
| `loading` | 连接中状态、进度指示和辅助文字清晰 |
| `error` | 错误横幅与重试入口可见，不遮挡任务列表 |
| `long` | 标题、路径、分支、模型均单行截断，卡片高度不变 |
| `many` | 一屏最多四张卡片，更多任务可滚动到底，Header 与 Footer 始终固定 |

辅助功能树可识别筛选按钮、状态、任务摘要、Pin 和“在 Codex 中打开”动作。Reduce Transparency 与完整键盘/VoiceOver 操作仍应在发布签名前做一次人工系统设置验收。
