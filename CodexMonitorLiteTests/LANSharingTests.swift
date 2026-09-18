import XCTest
@testable import CodexMonitorLite

final class LANSharingTests: XCTestCase {
    func testSnapshotContainsOnlyActiveSafeFields() throws {
        let now = Date(timeIntervalSince1970: 1_789_575_000)
        let active = makeTask(id: "active", status: .running, now: now)
        let inactive = makeTask(id: "inactive", status: .inactive, now: now)

        let snapshot = LANTaskSnapshot(tasks: [active, inactive], now: now, revision: "revision-1")
        let line = try snapshot.encodedLine()
        let decoded = try JSONDecoder().decode(LANTaskSnapshot.self, from: line.dropLast())

        XCTAssertEqual(line.last, 0x0A)
        XCTAssertEqual(decoded.tasks.map(\.id), ["active"])
        XCTAssertEqual(decoded.tasks.first?.project, "project")
        XCTAssertEqual(decoded.schemaVersion, 1)

        let json = try XCTUnwrap(String(data: line, encoding: .utf8))
        XCTAssertFalse(json.contains("/Users/example/private"))
        XCTAssertFalse(json.contains("secret-branch"))
        XCTAssertFalse(json.contains("private-model"))
        XCTAssertFalse(json.contains("prompt contents"))
        XCTAssertFalse(json.contains("codex://"))
    }

    private func makeTask(id: String, status: MonitorTaskStatus, now: Date) -> MonitoredTask {
        MonitoredTask(
            id: id,
            externalTaskId: "external-\(id)",
            sourceKind: "codex",
            title: "任务 \(id)",
            summary: "prompt contents",
            status: status,
            priority: .normal,
            projectName: "project",
            workspaceDisplayPath: "/Users/example/private",
            branch: "secret-branch",
            model: "private-model",
            currentAction: "private action",
            startedAt: now.addingTimeInterval(-30),
            lastActivityAt: now,
            completedAt: nil,
            lastViewedAt: nil,
            durationMs: nil,
            deepLink: URL(string: "codex://threads/\(id)")
        )
    }
}
