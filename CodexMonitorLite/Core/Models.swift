import Foundation

enum MonitorTaskStatus: String, Codable, CaseIterable, Sendable {
    case running
    case needsAttention
    case awaitingReview
    case inactive

    var title: String {
        switch self {
        case .running: "运行中"
        case .needsAttention: "需要你"
        case .awaitingReview: "待查看"
        case .inactive: "已查看"
        }
    }

    var isActive: Bool { self != .inactive }
}

enum MonitorFilter: String, CaseIterable, Identifiable {
    case all
    case running
    case needsAttention
    case awaitingReview

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "全部"
        case .running: "运行中"
        case .needsAttention: "需要你"
        case .awaitingReview: "待查看"
        }
    }

    func includes(_ task: MonitoredTask) -> Bool {
        switch self {
        case .all: true
        case .running: task.status == .running
        case .needsAttention: task.status == .needsAttention
        case .awaitingReview: task.status == .awaitingReview
        }
    }
}

enum EventPriority: String, Codable, Sendable {
    case low
    case normal
    case high
    case critical
}

struct EventSourceDescriptor: Codable, Equatable, Sendable {
    let kind: String
    let instanceId: String
}

/// Versioned, cloud-safe event contract. Source adapters must not place prompts,
/// source code, terminal output, or absolute paths in this value.
struct StandardEvent: Codable, Equatable, Identifiable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let eventId: String
    let source: EventSourceDescriptor
    let type: String
    let priority: EventPriority
    let title: String
    let summary: String?
    let status: MonitorTaskStatus
    let occurredAt: Date
    let receivedAt: Date
    let durationMs: Int64?
    let metadata: [String: String]

    var id: String { eventId }

    init(
        schemaVersion: Int = StandardEvent.currentSchemaVersion,
        eventId: String,
        source: EventSourceDescriptor,
        type: String,
        priority: EventPriority,
        title: String,
        summary: String?,
        status: MonitorTaskStatus,
        occurredAt: Date,
        receivedAt: Date,
        durationMs: Int64?,
        metadata: [String: String]
    ) {
        self.schemaVersion = schemaVersion
        self.eventId = eventId
        self.source = source
        self.type = type
        self.priority = priority
        self.title = title
        self.summary = summary
        self.status = status
        self.occurredAt = occurredAt
        self.receivedAt = receivedAt
        self.durationMs = durationMs
        self.metadata = metadata
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case eventId
        case source
        case type
        case priority
        case title
        case summary
        case status
        case occurredAt
        case receivedAt
        case durationMs
        case metadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        eventId = try container.decode(String.self, forKey: .eventId)
        source = try container.decode(EventSourceDescriptor.self, forKey: .source)
        type = try container.decode(String.self, forKey: .type)
        priority = try container.decode(EventPriority.self, forKey: .priority)
        title = try container.decode(String.self, forKey: .title)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        status = try container.decode(MonitorTaskStatus.self, forKey: .status)
        durationMs = try container.decodeIfPresent(Int64.self, forKey: .durationMs)
        metadata = try container.decode([String: String].self, forKey: .metadata)

        let occurredAtValue = try container.decode(String.self, forKey: .occurredAt)
        guard let occurredAt = EventTime.parseRFC3339(occurredAtValue) else {
            throw DecodingError.dataCorruptedError(
                forKey: .occurredAt,
                in: container,
                debugDescription: "Expected an RFC 3339 timestamp"
            )
        }
        self.occurredAt = occurredAt

        let receivedAtValue = try container.decode(String.self, forKey: .receivedAt)
        guard let receivedAt = EventTime.parseRFC3339(receivedAtValue) else {
            throw DecodingError.dataCorruptedError(
                forKey: .receivedAt,
                in: container,
                debugDescription: "Expected an RFC 3339 timestamp"
            )
        }
        self.receivedAt = receivedAt
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(eventId, forKey: .eventId)
        try container.encode(source, forKey: .source)
        try container.encode(type, forKey: .type)
        try container.encode(priority, forKey: .priority)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(summary, forKey: .summary)
        try container.encode(status, forKey: .status)
        try container.encode(EventTime.rfc3339Milliseconds(occurredAt), forKey: .occurredAt)
        try container.encode(EventTime.rfc3339Milliseconds(receivedAt), forKey: .receivedAt)
        try container.encodeIfPresent(durationMs, forKey: .durationMs)
        try container.encode(metadata, forKey: .metadata)
    }
}

/// Local-only context. It is deliberately excluded from EventPublisher.
struct LocalTaskContext: Codable, Equatable, Sendable {
    let externalTaskId: String
    let displayTitle: String
    let projectName: String
    let workspaceDisplayPath: String?
    let branch: String?
    let model: String?
    let currentAction: String?
    let startedAt: Date?
    let completedAt: Date?
    let deepLink: URL?
}

struct SourceUpdate: Equatable, Sendable {
    let event: StandardEvent
    let local: LocalTaskContext
}

struct MonitoredTask: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let externalTaskId: String
    let sourceKind: String
    var title: String
    var summary: String?
    var status: MonitorTaskStatus
    var priority: EventPriority
    var projectName: String
    var workspaceDisplayPath: String?
    var branch: String?
    var model: String?
    var currentAction: String?
    var startedAt: Date?
    var lastActivityAt: Date
    var completedAt: Date?
    var lastViewedAt: Date?
    var durationMs: Int64?
    var deepLink: URL?

    func elapsedMilliseconds(at now: Date = Date()) -> Int64? {
        if let durationMs { return durationMs }
        guard let startedAt else { return nil }
        let end = completedAt ?? now
        return max(0, Int64((end.timeIntervalSince(startedAt) * 1_000).rounded()))
    }
}

enum SourceConnectionState: Equatable, Sendable {
    case connecting
    case connected
    case failed(String)

    var label: String {
        switch self {
        case .connecting: "连接中"
        case .connected: "已连接"
        case .failed: "连接异常"
        }
    }
}
