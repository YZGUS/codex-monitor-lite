import Foundation

enum FixtureKind: String {
    case normal
    case empty
    case loading
    case error
    case long
    case many
}

struct FixtureSourceAdapter: SourceAdapter {
    let sourceKind = "fixture"
    let kind: FixtureKind

    func makeStream() -> AsyncThrowingStream<SourceMessage, Error> {
        AsyncThrowingStream { continuation in
            if kind == .loading {
                let task = Task {
                    try? await Task.sleep(nanoseconds: 3_600_000_000_000)
                    continuation.finish()
                }
                continuation.onTermination = { _ in task.cancel() }
                return
            }

            continuation.yield(.connected)
            let updates = fixtureUpdates()
            updates.forEach { continuation.yield(.update($0)) }
            continuation.yield(.snapshot(
                sourceKind: sourceKind,
                externalTaskIds: Set(updates.map(\.local.externalTaskId))
            ))
            if kind == .error {
                continuation.finish(throwing: FixtureError.disconnected)
            } else {
                continuation.finish()
            }
        }
    }

    private func fixtureUpdates() -> [SourceUpdate] {
        if kind == .empty || kind == .loading { return [] }
        let count = kind == .many ? 64 : (kind == .long ? 1 : 6)
        return (0..<count).map { index in
            let status: MonitorTaskStatus = switch index % 6 {
            case 0, 1, 2: .running
            case 3: .needsAttention
            case 4: .awaitingReview
            default: .inactive
            }
            let baseTitles = [
                "ES 查询长度限制",
                "统一 service_name 监控逻辑",
                "调研 Codex Hook",
                "ClickHouse SQL 优化",
                "Git merge 文件暴增原因",
                "前端构建失败排查"
            ]
            let longTitle = "这是一个用于验证超长标题不会挤压状态标签、破坏卡片高度或产生横向滚动的 Codex 任务标题，同时还需要保持中文与英文 mixed content 的可读性"
            let title = kind == .long ? longTitle : "\(baseTitles[index % baseTitles.count])\(index >= 6 ? " #\(index + 1)" : "")"
            let now = Date()
            let startedAt = now.addingTimeInterval(TimeInterval(-(index + 2) * 95))
            let completedAt = status == .awaitingReview || status == .inactive
                ? now.addingTimeInterval(TimeInterval(-(index + 1) * 420))
                : nil
            let occurredAt = completedAt ?? now.addingTimeInterval(TimeInterval(-index * 13))
            let duration = completedAt.map { Int64($0.timeIntervalSince(startedAt) * 1_000) }
            let action: String = switch status {
            case .running: "正在分析本地事件…"
            case .needsAttention: "等待你的授权"
            case .awaitingReview: "任务已完成"
            case .inactive: "已查看"
            }
            let taskId = "fixture-\(index)"
            let event = StandardEvent(
                eventId: "fixture:\(taskId):\(status.rawValue)",
                source: EventSourceDescriptor(kind: sourceKind, instanceId: "fixture"),
                type: "task.\(status.rawValue)",
                priority: status == .needsAttention ? .high : .normal,
                title: "Codex 测试任务",
                summary: action,
                status: status,
                occurredAt: occurredAt,
                receivedAt: now,
                durationMs: duration,
                metadata: ["taskId": taskId, "project": "monitor-center"]
            )
            let local = LocalTaskContext(
                externalTaskId: taskId,
                displayTitle: title,
                projectName: "monitor-center",
                workspaceDisplayPath: kind == .long ? "~/work/一个非常长的项目目录名称/monitor-center" : "~/work/monitor-center",
                branch: kind == .long ? "feature/very-long-branch-name-for-layout-verification" : "feature/monitor",
                model: kind == .long ? "gpt-5.6-sol-ultra-long-model-name" : "gpt-5.6-sol",
                currentAction: action,
                startedAt: startedAt,
                completedAt: completedAt,
                deepLink: URL(string: "codex://threads/\(taskId)")
            )
            return SourceUpdate(event: event, local: local)
        }
    }

    private enum FixtureError: LocalizedError {
        case disconnected
        var errorDescription: String? { "无法读取 Codex 状态" }
    }
}
