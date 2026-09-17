import XCTest
@testable import CodexMonitorLite

final class EventTimeTests: XCTestCase {
    func testStandardEventUsesRFC3339UTCMilliseconds() throws {
        let date = try XCTUnwrap(EventTime.parseRFC3339("2026-09-17T12:34:56.789Z"))
        let event = StandardEvent(
            eventId: "event-1",
            source: EventSourceDescriptor(kind: "test", instanceId: "local"),
            type: "task.running",
            priority: .normal,
            title: "测试任务",
            summary: nil,
            status: .running,
            occurredAt: date,
            receivedAt: date,
            durationMs: 1_234,
            metadata: [:]
        )

        // The wire contract must hold even when a future publisher uses the
        // standard encoder instead of an app-specific helper.
        let data = try JSONEncoder().encode(event)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["occurredAt"] as? String, "2026-09-17T12:34:56.789Z")
        XCTAssertEqual(object["receivedAt"] as? String, "2026-09-17T12:34:56.789Z")
        XCTAssertEqual(object["durationMs"] as? Int, 1_234)

        let decoded = try JSONDecoder().decode(StandardEvent.self, from: data)
        XCTAssertEqual(decoded, event)
    }

    func testCompactDurationUsesMilliseconds() {
        XCTAssertEqual(EventTime.compactDuration(milliseconds: 8_000), "8s")
        XCTAssertEqual(EventTime.compactDuration(milliseconds: 498_000), "8m 18s")
        XCTAssertEqual(EventTime.compactDuration(milliseconds: 3_723_000), "1h 02m")
    }
}
