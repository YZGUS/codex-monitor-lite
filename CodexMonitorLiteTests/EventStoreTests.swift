import XCTest
@testable import CodexMonitorLite

final class EventStoreTests: XCTestCase {
    func testStatePersistsAcrossStoreInstances() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexMonitorLiteTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("state.json")
        let store = JSONTaskStore(fileURL: url)
        let now = Date(timeIntervalSince1970: 1_789_575_000.123)
        let task = MonitoredTask(
            id: "test:1",
            externalTaskId: "1",
            sourceKind: "test",
            title: "任务",
            summary: nil,
            status: .awaitingReview,
            priority: .normal,
            projectName: "project",
            workspaceDisplayPath: "~/project",
            branch: nil,
            model: nil,
            currentAction: nil,
            startedAt: now,
            lastActivityAt: now,
            completedAt: now,
            lastViewedAt: nil,
            durationMs: 100,
            deepLink: nil
        )
        let expected = PersistedMonitorState(tasks: [task], processedEventIds: ["event-1"])

        try store.save(expected)
        XCTAssertEqual(try JSONTaskStore(fileURL: url).load(), expected)
    }
}
