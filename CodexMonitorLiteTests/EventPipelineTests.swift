import XCTest
@testable import CodexMonitorLite

final class EventPipelineTests: XCTestCase {
    func testReducerMapsStateAndDeduplicatesEvent() {
        let now = Date(timeIntervalSince1970: 1_789_575_000)
        var reducer = EventReducer()
        let update = makeUpdate(eventId: "one", status: .running, occurredAt: now)

        XCTAssertTrue(reducer.apply(update))
        XCTAssertFalse(reducer.apply(update))
        XCTAssertEqual(reducer.tasks.count, 1)
        XCTAssertEqual(reducer.tasks[0].status, .running)
        XCTAssertEqual(reducer.persistedState().processedEventIds, ["one"])
    }

    func testViewedCompletionBecomesInactiveUntilNewRun() {
        let completedAt = Date(timeIntervalSince1970: 1_789_575_100)
        var reducer = EventReducer()
        XCTAssertTrue(reducer.apply(makeUpdate(
            eventId: "complete",
            status: .awaitingReview,
            occurredAt: completedAt,
            completedAt: completedAt
        )))
        let id = try! XCTUnwrap(reducer.tasks.first?.id)
        XCTAssertTrue(reducer.markViewed(taskId: id, at: completedAt.addingTimeInterval(1)))
        XCTAssertEqual(reducer.tasks.first?.status, .inactive)

        XCTAssertTrue(reducer.apply(makeUpdate(
            eventId: "next-run",
            status: .running,
            occurredAt: completedAt.addingTimeInterval(60)
        )))
        XCTAssertEqual(reducer.tasks.first?.status, .running)
        XCTAssertNil(reducer.tasks.first?.lastViewedAt)
    }

    func testUnreadCompletionDoesNotExpireWhenSourceClassifiesItAsOld() {
        let completedAt = Date(timeIntervalSince1970: 1_789_575_100)
        var reducer = EventReducer()
        XCTAssertTrue(reducer.apply(makeUpdate(
            eventId: "recent-completion",
            status: .awaitingReview,
            occurredAt: completedAt,
            completedAt: completedAt
        )))

        XCTAssertTrue(reducer.apply(makeUpdate(
            eventId: "old-completion-refresh",
            status: .inactive,
            occurredAt: completedAt.addingTimeInterval(86_401),
            completedAt: completedAt
        )))
        XCTAssertEqual(reducer.tasks.first?.status, .awaitingReview)
    }

    func testSnapshotRemovesTasksNoLongerReportedBySource() {
        let now = Date(timeIntervalSince1970: 1_789_575_000)
        var reducer = EventReducer()
        XCTAssertTrue(reducer.apply(makeUpdate(eventId: "one", status: .running, occurredAt: now)))
        XCTAssertTrue(reducer.reconcile(sourceKind: "test", externalTaskIds: []))
        XCTAssertTrue(reducer.tasks.isEmpty)
    }

    private func makeUpdate(
        eventId: String,
        status: MonitorTaskStatus,
        occurredAt: Date,
        completedAt: Date? = nil
    ) -> SourceUpdate {
        let event = StandardEvent(
            eventId: eventId,
            source: EventSourceDescriptor(kind: "test", instanceId: "local"),
            type: "task.\(status.rawValue)",
            priority: .normal,
            title: "任务",
            summary: "安全摘要",
            status: status,
            occurredAt: occurredAt,
            receivedAt: occurredAt,
            durationMs: completedAt == nil ? nil : 5_000,
            metadata: ["taskId": "task-1"]
        )
        let local = LocalTaskContext(
            externalTaskId: "task-1",
            displayTitle: "任务",
            projectName: "project",
            workspaceDisplayPath: "~/project",
            branch: "main",
            model: "model",
            currentAction: "处理中",
            startedAt: occurredAt.addingTimeInterval(-5),
            completedAt: completedAt,
            deepLink: URL(string: "codex://threads/task-1")
        )
        return SourceUpdate(event: event, local: local)
    }
}
