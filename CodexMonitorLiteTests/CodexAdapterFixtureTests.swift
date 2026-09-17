import XCTest
@testable import CodexMonitorLite

final class CodexAdapterFixtureTests: XCTestCase {
    func testThreadListFixtureDecodes() throws {
        let data = try fixtureData("CodexThreadList", extension: "json")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let response = try CodexThreadListDecoder.decode(try XCTUnwrap(object["result"]))
        XCTAssertEqual(response.data.count, 2)
        XCTAssertEqual(response.data[0].status.type, "notLoaded")
        XCTAssertEqual(response.data[0].gitInfo?.branch, "main")
    }

    func testRecentThreadFilterKeepsOnlyLast24Hours() {
        let now = Date(timeIntervalSince1970: 1_789_575_000)
        func thread(id: String, age: TimeInterval) -> CodexThread {
            CodexThread(
                id: id,
                name: id,
                cwd: "/Users/example/project",
                model: "gpt-test",
                updatedAt: Int64(now.addingTimeInterval(-age).timeIntervalSince1970),
                status: .init(type: "notLoaded", activeFlags: nil),
                path: nil,
                gitInfo: nil
            )
        }

        let result = CodexThreadRecency.recentThreads(
            [
                thread(id: "recent", age: 60),
                thread(id: "boundary", age: 24 * 60 * 60),
                thread(id: "old", age: 24 * 60 * 60 + 1)
            ],
            relativeTo: now
        )

        XCTAssertEqual(result.map(\.id), ["recent", "boundary"])
    }

    func testRolloutLifecycleDetectsRunningAndCompleted() throws {
        let running = try XCTUnwrap(fixtureURL("CodexRolloutRunning", extension: "jsonl"))
        let completed = try XCTUnwrap(fixtureURL("CodexRolloutCompleted", extension: "jsonl"))

        let runningActivity = CodexRolloutReader.read(path: running.path)
        XCTAssertTrue(runningActivity.isRunning)
        XCTAssertEqual(runningActivity.currentAction, "正在执行命令…")
        XCTAssertNotNil(runningActivity.startedAt)

        let completedActivity = CodexRolloutReader.read(path: completed.path)
        XCTAssertFalse(completedActivity.isRunning)
        XCTAssertEqual(completedActivity.durationMs, 44_842)
        XCTAssertEqual(completedActivity.currentAction, "任务已完成")
    }

    func testRolloutDetectsApprovalWithoutReadingRequestContent() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-monitor-approval-\(UUID().uuidString).jsonl")
        let content = """
        {"timestamp":"2026-09-17T12:00:00.000Z","type":"event_msg","payload":{"type":"task_started","started_at":1789646400}}
        {"timestamp":"2026-09-17T12:00:01.000Z","type":"event_msg","payload":{"type":"exec_approval_request","command":"sensitive content must not be parsed"}}
        """
        try Data(content.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let activity = CodexRolloutReader.read(path: url.path)
        XCTAssertEqual(activity.attentionReason, .approval)
        XCTAssertEqual(activity.currentAction, "等待你的授权")
    }

    func testSilentLongRunningTaskRemainsRunning() {
        let receivedAt = Date(timeIntervalSince1970: 1_789_575_000)
        let oldActivityAt = receivedAt.addingTimeInterval(-3_600)
        let thread = CodexThread(
            id: "thread-long",
            name: "长任务",
            cwd: "/Users/example/project",
            model: "gpt-test",
            updatedAt: Int64(oldActivityAt.timeIntervalSince1970),
            status: .init(type: "notLoaded", activeFlags: nil),
            path: nil,
            gitInfo: nil
        )
        let activity = CodexRolloutActivity(
            isRunning: true,
            startedAt: oldActivityAt,
            lastEventAt: oldActivityAt,
            currentAction: "正在处理任务…"
        )

        let update = CodexUpdateFactory.makeUpdate(
            from: thread,
            receivedAt: receivedAt,
            activity: activity
        )
        XCTAssertEqual(update.event.status, .running)
    }

    func testStaleUnconfirmedRolloutBecomesInactive() {
        let receivedAt = Date(timeIntervalSince1970: 1_789_575_000)
        let staleActivityAt = receivedAt.addingTimeInterval(-25 * 60 * 60)
        let thread = CodexThread(
            id: "thread-stale",
            name: "旧任务",
            cwd: "/Users/example/project",
            model: "gpt-test",
            updatedAt: Int64(staleActivityAt.timeIntervalSince1970),
            status: .init(type: "notLoaded", activeFlags: nil),
            path: nil,
            gitInfo: nil
        )
        let activity = CodexRolloutActivity(
            isRunning: true,
            attentionReason: .approval,
            startedAt: staleActivityAt,
            lastEventAt: staleActivityAt,
            currentAction: "等待你的授权"
        )

        let update = CodexUpdateFactory.makeUpdate(
            from: thread,
            receivedAt: receivedAt,
            activity: activity
        )
        XCTAssertEqual(update.event.status, .inactive)
    }

    func testStandardEventExcludesAbsolutePathAndPrompt() throws {
        let thread = CodexThread(
            id: "thread-1",
            name: "安全标题",
            cwd: "/Users/example/private/project",
            model: "gpt-test",
            updatedAt: 1_789_575_000,
            status: .init(type: "idle", activeFlags: nil),
            path: nil,
            gitInfo: .init(branch: "main")
        )
        let update = CodexUpdateFactory.makeUpdate(
            from: thread,
            receivedAt: Date(timeIntervalSince1970: 1_789_575_100)
        )
        let encoded = try EventTime.encoder().encode(update.event)
        let text = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        XCTAssertFalse(text.contains("/Users/example"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("prompt"))
        XCTAssertFalse(text.contains("安全标题"))
        XCTAssertEqual(update.local.displayTitle, "安全标题")
        XCTAssertEqual(update.local.workspaceDisplayPath, "…/project")
    }

    private func fixtureData(_ name: String, extension ext: String) throws -> Data {
        try Data(contentsOf: try XCTUnwrap(fixtureURL(name, extension: ext)))
    }

    private func fixtureURL(_ name: String, extension ext: String) -> URL? {
        Bundle(for: Self.self).url(forResource: name, withExtension: ext)
    }
}
