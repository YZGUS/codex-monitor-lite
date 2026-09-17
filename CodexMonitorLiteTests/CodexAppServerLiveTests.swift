import XCTest
@testable import CodexMonitorLite

final class CodexAppServerLiveTests: XCTestCase {
    func testReadOnlyThreadListAgainstInstalledCodex() async throws {
        guard ProcessInfo.processInfo.environment["CODEX_LIVE_TEST"] == "1" else {
            throw XCTSkip("Set CODEX_LIVE_TEST=1 to run the local read-only integration test")
        }

        let client = CodexAppServerClient(command: CodexExecutableLocator().command())
        defer { client.stop() }
        let result = try await withThrowingTaskGroup(of: CodexThreadListResponse.self) { group in
            group.addTask {
                try await client.start()
                let payload = try await client.request(
                    method: "thread/list",
                    params: [
                        "limit": 2,
                        "sortKey": "recency_at",
                        "sortDirection": "desc",
                        "archived": false,
                        "useStateDbOnly": true
                    ]
                )
                return try CodexThreadListDecoder.decode(payload)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 10_000_000_000)
                client.stop()
                throw LiveTestError.timedOut
            }
            let first = try await group.next()!
            group.cancelAll()
            return first
        }
        XCTAssertLessThanOrEqual(result.data.count, 2)
    }

    private enum LiveTestError: Error {
        case timedOut
    }
}
