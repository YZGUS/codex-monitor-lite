import Foundation

enum CodexSourceError: LocalizedError {
    case executableNotFound
    case processEnded
    case malformedResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .executableNotFound: "未找到 Codex 可执行文件"
        case .processEnded: "Codex App Server 已停止"
        case .malformedResponse: "Codex App Server 返回了无法识别的数据"
        case .server(let message): message
        }
    }
}

struct CodexSourceAdapter: SourceAdapter, @unchecked Sendable {
    let sourceKind = "codex"
    private let pollInterval: TimeInterval
    private let now: @Sendable () -> Date
    private let executableLocator: CodexExecutableLocator

    init(
        pollInterval: TimeInterval = 2,
        now: @escaping @Sendable () -> Date = { Date() },
        executableLocator: CodexExecutableLocator = CodexExecutableLocator()
    ) {
        self.pollInterval = pollInterval
        self.now = now
        self.executableLocator = executableLocator
    }

    func makeStream() -> AsyncThrowingStream<SourceMessage, Error> {
        AsyncThrowingStream { continuation in
            let client = CodexAppServerClient(command: executableLocator.command())
            let worker = Task {
                var rolloutCache = CodexRolloutCache()
                do {
                    try await client.start()
                    continuation.yield(.connected)

                    while !Task.isCancelled {
                        let payload = try await client.request(
                            method: "thread/list",
                            params: [
                                "limit": 100,
                                "sortKey": "recency_at",
                                "sortDirection": "desc",
                                "archived": false,
                                "useStateDbOnly": true
                            ]
                        )
                        let response = try CodexThreadListDecoder.decode(payload)
                        let receivedAt = now()
                        let recentThreads = CodexThreadRecency.recentThreads(
                            response.data,
                            relativeTo: receivedAt
                        )
                        for thread in recentThreads {
                            let update = CodexUpdateFactory.makeUpdate(
                                from: thread,
                                receivedAt: receivedAt,
                                activity: rolloutCache.read(path: thread.path)
                            )
                            continuation.yield(.update(update))
                        }
                        continuation.yield(.snapshot(
                            sourceKind: sourceKind,
                            externalTaskIds: Set(recentThreads.map(\.id))
                        ))
                        rolloutCache.retain(paths: Set(recentThreads.compactMap(\.path)))

                        try await Task.sleep(
                            nanoseconds: UInt64(max(0.5, pollInterval) * 1_000_000_000)
                        )
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
                client.stop()
            }

            continuation.onTermination = { _ in
                worker.cancel()
                client.stop()
            }
        }
    }
}

struct CodexExecutableLocator: Sendable {
    struct Command: Sendable {
        let executableURL: URL
        let arguments: [String]
    }

    private let environment: [String: String]

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.environment = environment
    }

    func command() -> Command? {
        var candidates: [String] = []
        if let override = environment["CODEX_EXECUTABLE"], !override.isEmpty {
            candidates.append(override)
        }
        candidates.append(contentsOf: [
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ])

        if let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return Command(
                executableURL: URL(fileURLWithPath: path),
                arguments: ["app-server", "--listen", "stdio://"]
            )
        }

        return Command(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["codex", "app-server", "--listen", "stdio://"]
        )
    }
}

final class CodexAppServerClient: @unchecked Sendable {
    private let command: CodexExecutableLocator.Command?
    private let queue = DispatchQueue(label: "com.yzgus.codex-monitor-lite.app-server")
    private var process: Process?
    private var inputHandle: FileHandle?
    private var outputBuffer = Data()
    private var nextRequestId = 1
    private var pending: [Int: (Result<Any, Error>) -> Void] = [:]

    init(command: CodexExecutableLocator.Command?) {
        self.command = command
    }

    func start() async throws {
        guard let command else { throw CodexSourceError.executableNotFound }

        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = command.executableURL
        process.arguments = command.arguments
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.queue.async { self?.consume(data) }
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }
        process.terminationHandler = { [weak self] _ in
            self?.queue.async { self?.failPending(with: CodexSourceError.processEnded) }
        }

        try process.run()
        self.process = process
        self.inputHandle = inputPipe.fileHandleForWriting

        _ = try await request(
            method: "initialize",
            params: [
                "clientInfo": [
                    "name": "codex-monitor-lite",
                    "title": "Codex Monitor Lite",
                    "version": "0.1.0"
                ],
                "capabilities": [
                    "experimentalApi": false,
                    "requestAttestation": false
                ]
            ]
        )
        try notify(method: "initialized")
    }

    func request(method: String, params: [String: Any]) async throws -> Any {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                let requestId = self.nextRequestId
                self.nextRequestId += 1
                do {
                    self.pending[requestId] = { result in continuation.resume(with: result) }
                    try self.write(["id": requestId, "method": method, "params": params])
                } catch {
                    self.pending.removeValue(forKey: requestId)
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func notify(method: String) throws {
        try queue.sync { try write(["method": method]) }
    }

    func stop() {
        queue.async {
            self.inputHandle?.closeFile()
            self.inputHandle = nil
            if let process = self.process, process.isRunning { process.terminate() }
            self.process = nil
            self.failPending(with: CancellationError())
        }
    }

    private func write(_ object: [String: Any]) throws {
        guard let inputHandle else { throw CodexSourceError.processEnded }
        var data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        data.append(0x0A)
        try inputHandle.write(contentsOf: data)
    }

    private func consume(_ data: Data) {
        outputBuffer.append(data)
        while let newline = outputBuffer.firstIndex(of: 0x0A) {
            var line = outputBuffer.prefix(upTo: newline)
            outputBuffer.removeSubrange(...newline)
            if line.last == 0x0D { line = line.dropLast() }
            guard !line.isEmpty else { continue }
            handleLine(Data(line))
        }
    }

    private func handleLine(_ data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = (object["id"] as? NSNumber)?.intValue,
              let callback = pending.removeValue(forKey: id) else {
            return // Notifications are intentionally ignored by this read-only adapter.
        }

        if let error = object["error"] as? [String: Any] {
            callback(.failure(CodexSourceError.server(error["message"] as? String ?? "Codex 请求失败")))
        } else if let result = object["result"] {
            callback(.success(result))
        } else {
            callback(.failure(CodexSourceError.malformedResponse))
        }
    }

    private func failPending(with error: Error) {
        let callbacks = pending.values
        pending.removeAll()
        callbacks.forEach { $0(.failure(error)) }
    }
}

struct CodexThreadListResponse: Decodable, Equatable {
    let data: [CodexThread]
}

struct CodexThread: Decodable, Equatable {
    struct Status: Decodable, Equatable {
        let type: String
        let activeFlags: [String]?
    }

    struct GitInfo: Decodable, Equatable {
        let branch: String?
    }

    let id: String
    let name: String?
    let cwd: String
    let model: String?
    let updatedAt: Int64
    let status: Status
    let path: String?
    let gitInfo: GitInfo?
}

enum CodexThreadRecency {
    static let lookbackInterval: TimeInterval = 24 * 60 * 60

    static func recentThreads(
        _ threads: [CodexThread],
        relativeTo referenceDate: Date
    ) -> [CodexThread] {
        threads.filter { thread in
            let updatedAt = Date(timeIntervalSince1970: TimeInterval(thread.updatedAt))
            return referenceDate.timeIntervalSince(updatedAt) <= lookbackInterval
        }
    }
}

enum CodexThreadListDecoder {
    static func decode(_ payload: Any) throws -> CodexThreadListResponse {
        guard JSONSerialization.isValidJSONObject(payload) else {
            throw CodexSourceError.malformedResponse
        }
        let data = try JSONSerialization.data(withJSONObject: payload)
        return try JSONDecoder().decode(CodexThreadListResponse.self, from: data)
    }
}

struct CodexRolloutActivity: Equatable {
    enum AttentionReason: Equatable {
        case approval
        case userInput
    }

    var isRunning = false
    var attentionReason: AttentionReason?
    var turnId: String?
    var startedAt: Date?
    var completedAt: Date?
    var durationMs: Int64?
    var lastEventAt: Date?
    var currentAction: String?
}

struct CodexRolloutCache {
    private struct Stamp: Equatable {
        let size: UInt64
        let modifiedAt: Date?
    }

    private var entries: [String: (stamp: Stamp, activity: CodexRolloutActivity)] = [:]

    mutating func read(path: String?) -> CodexRolloutActivity {
        guard let path, !path.isEmpty,
              let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = (attributes[.size] as? NSNumber)?.uint64Value else {
            return CodexRolloutActivity()
        }
        let stamp = Stamp(size: size, modifiedAt: attributes[.modificationDate] as? Date)
        if let cached = entries[path], cached.stamp == stamp { return cached.activity }

        let activity = CodexRolloutReader.read(path: path)
        entries[path] = (stamp, activity)
        return activity
    }

    mutating func retain(paths: Set<String>) {
        entries = entries.filter { paths.contains($0.key) }
    }
}

enum CodexRolloutReader {
    static let maximumTailBytes: UInt64 = 8 * 1_024 * 1_024

    static func read(path: String?) -> CodexRolloutActivity {
        guard let path, !path.isEmpty else { return CodexRolloutActivity() }
        let url = URL(fileURLWithPath: path)
        guard let handle = try? FileHandle(forReadingFrom: url) else { return CodexRolloutActivity() }
        defer { try? handle.close() }

        let end = (try? handle.seekToEnd()) ?? 0
        let start = end > maximumTailBytes ? end - maximumTailBytes : 0
        try? handle.seek(toOffset: start)
        let data = (try? handle.readToEnd()) ?? Data()
        var lines = data.split(separator: 0x0A, omittingEmptySubsequences: true)
        if start > 0, !lines.isEmpty { lines.removeFirst() }

        var activity = CodexRolloutActivity()
        var sawLifecycleEvent = false
        var sawItemAfterLifecycle = false

        for rawLine in lines {
            guard let object = try? JSONSerialization.jsonObject(with: Data(rawLine)) as? [String: Any],
                  object["type"] as? String == "event_msg",
                  let payload = object["payload"] as? [String: Any],
                  let payloadType = payload["type"] as? String else { continue }

            let eventDate = (object["timestamp"] as? String).flatMap(EventTime.parseRFC3339)
            if let eventDate { activity.lastEventAt = eventDate }

            switch payloadType {
            case "task_started":
                sawLifecycleEvent = true
                sawItemAfterLifecycle = false
                activity.isRunning = true
                activity.attentionReason = nil
                activity.turnId = payload["turn_id"] as? String
                activity.startedAt = EventTime.date(unixSeconds: int64(payload["started_at"])) ?? eventDate
                activity.completedAt = nil
                activity.durationMs = nil
                activity.currentAction = "正在处理任务…"

            case "task_complete":
                sawLifecycleEvent = true
                activity.isRunning = false
                activity.attentionReason = nil
                activity.turnId = payload["turn_id"] as? String ?? activity.turnId
                activity.startedAt = EventTime.date(unixSeconds: int64(payload["started_at"])) ?? activity.startedAt
                activity.completedAt = EventTime.date(unixSeconds: int64(payload["completed_at"])) ?? eventDate
                activity.durationMs = int64(payload["duration_ms"])
                activity.currentAction = "任务已完成"

            case "exec_approval_request", "apply_patch_approval_request", "request_permissions":
                activity.isRunning = true
                activity.attentionReason = .approval
                activity.currentAction = "等待你的授权"

            case "request_user_input", "elicitation_request":
                activity.isRunning = true
                activity.attentionReason = .userInput
                activity.currentAction = "等待你的输入"

            case "item_started", "item_completed":
                sawItemAfterLifecycle = true
                activity.attentionReason = nil
                if activity.isRunning || !sawLifecycleEvent {
                    let item = payload["item"] as? [String: Any]
                    activity.currentAction = safeAction(for: item?["type"] as? String)
                }

            default:
                continue
            }
        }

        // A very large active turn may begin before the bounded tail. A recent
        // item without a following task_complete still proves current activity.
        if !sawLifecycleEvent, sawItemAfterLifecycle, let lastEventAt = activity.lastEventAt,
           Date().timeIntervalSince(lastEventAt) < 15 * 60 {
            activity.isRunning = true
            activity.currentAction = activity.currentAction ?? "正在处理任务…"
        }
        return activity
    }

    private static func int64(_ value: Any?) -> Int64? {
        if let value = value as? NSNumber { return value.int64Value }
        if let value = value as? String { return Int64(value) }
        return nil
    }

    private static func safeAction(for itemType: String?) -> String {
        switch itemType?.lowercased() {
        case "commandexecution": "正在执行命令…"
        case "filechange": "正在修改文件…"
        case "mcptoolcall", "dynamictoolcall", "customtoolcall": "正在调用工具…"
        case "collabagenttoolcall", "subagentactivity": "正在协作处理…"
        case "websearch": "正在检索资料…"
        case "imagegeneration": "正在生成图像…"
        case "agentmessage": "正在整理结果…"
        default: "正在分析…"
        }
    }
}

enum CodexUpdateFactory {
    private static let unconfirmedActivityLifetime: TimeInterval = 24 * 60 * 60

    static func makeUpdate(
        from thread: CodexThread,
        receivedAt: Date,
        activity suppliedActivity: CodexRolloutActivity? = nil
    ) -> SourceUpdate {
        let activity = suppliedActivity ?? CodexRolloutReader.read(path: thread.path)
        let threadUpdatedAt = Date(timeIntervalSince1970: TimeInterval(thread.updatedAt))
        let lastActivityAt = max(activity.lastEventAt ?? .distantPast, threadUpdatedAt)
        let activityEvidenceAt = activity.lastEventAt ?? activity.startedAt ?? threadUpdatedAt
        let activityIsFresh = receivedAt.timeIntervalSince(activityEvidenceAt) <= unconfirmedActivityLifetime

        let status: MonitorTaskStatus
        let currentAction: String
        if thread.status.type == "systemError" {
            status = .needsAttention
            currentAction = "任务出现异常"
        } else if thread.status.activeFlags?.contains("waitingOnApproval") == true {
            status = .needsAttention
            currentAction = "等待你的授权"
        } else if thread.status.activeFlags?.contains("waitingOnUserInput") == true {
            status = .needsAttention
            currentAction = "等待你的输入"
        } else if activityIsFresh, activity.attentionReason == .approval {
            status = .needsAttention
            currentAction = "等待你的授权"
        } else if activityIsFresh, activity.attentionReason == .userInput {
            status = .needsAttention
            currentAction = "等待你的输入"
        } else if thread.status.type == "active" || (activityIsFresh && activity.isRunning) {
            status = .running
            currentAction = activity.currentAction ?? "正在处理任务…"
        } else if let completedAt = activity.completedAt,
                  receivedAt.timeIntervalSince(completedAt) < 24 * 60 * 60 {
            status = .awaitingReview
            currentAction = "任务已完成"
        } else {
            status = .inactive
            currentAction = activity.currentAction ?? "暂无活动"
        }

        let projectName = URL(fileURLWithPath: thread.cwd).lastPathComponent.nonEmpty ?? "Codex"
        let title = thread.name?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            ?? "\(projectName) · Codex 任务"
        let eventType: String = switch status {
        case .running: "task.running"
        case .needsAttention: "attention.required"
        case .awaitingReview: "task.completed"
        case .inactive: "task.inactive"
        }
        let priority: EventPriority = switch status {
        case .needsAttention: .high
        case .running, .awaitingReview: .normal
        case .inactive: .low
        }
        let eventStamp = Int64((lastActivityAt.timeIntervalSince1970 * 1_000).rounded())
        let eventId = "codex:\(thread.id):\(status.rawValue):\(eventStamp)"
        var metadata = [
            "taskId": thread.id,
            "project": projectName,
            "state": status.rawValue
        ]
        if let model = thread.model { metadata["model"] = model }
        if let branch = thread.gitInfo?.branch { metadata["branch"] = branch }

        let event = StandardEvent(
            eventId: eventId,
            source: EventSourceDescriptor(kind: "codex", instanceId: "local"),
            type: eventType,
            priority: priority,
            title: "\(projectName) · Codex 任务",
            summary: currentAction,
            status: status,
            occurredAt: lastActivityAt,
            receivedAt: receivedAt,
            durationMs: activity.durationMs,
            metadata: metadata
        )
        let local = LocalTaskContext(
            externalTaskId: thread.id,
            displayTitle: title,
            projectName: projectName,
            workspaceDisplayPath: displayPath(thread.cwd),
            branch: thread.gitInfo?.branch,
            model: thread.model,
            currentAction: currentAction,
            startedAt: activity.startedAt,
            completedAt: activity.completedAt,
            deepLink: URL(string: "codex://threads/\(thread.id)")
        )
        return SourceUpdate(event: event, local: local)
    }

    private static func displayPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return "…/\(URL(fileURLWithPath: path).lastPathComponent)"
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
