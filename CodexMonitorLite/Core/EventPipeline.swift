import Foundation

protocol SourceAdapter: Sendable {
    var sourceKind: String { get }
    func makeStream() -> AsyncThrowingStream<SourceMessage, Error>
}

enum SourceMessage: Equatable, Sendable {
    case connected
    case update(SourceUpdate)
    case snapshot(sourceKind: String, externalTaskIds: Set<String>)
}

protocol EventPublisher: Sendable {
    func publish(_ events: [StandardEvent]) async throws
}

struct NoopEventPublisher: EventPublisher {
    func publish(_ events: [StandardEvent]) async throws {}
}

struct PersistedMonitorState: Codable, Equatable {
    var tasks: [MonitoredTask]
    var processedEventIds: [String]

    static let empty = PersistedMonitorState(tasks: [], processedEventIds: [])
}

struct EventReducer {
    private(set) var tasksById: [String: MonitoredTask]
    private(set) var processedEventIds: [String]
    private var processedEventIdSet: Set<String>
    private let eventHistoryLimit: Int

    init(state: PersistedMonitorState = .empty, eventHistoryLimit: Int = 5_000) {
        self.tasksById = Dictionary(uniqueKeysWithValues: state.tasks.map { ($0.id, $0) })
        self.processedEventIds = Array(state.processedEventIds.suffix(eventHistoryLimit))
        self.processedEventIdSet = Set(self.processedEventIds)
        self.eventHistoryLimit = eventHistoryLimit
    }

    var tasks: [MonitoredTask] {
        tasksById.values.sorted {
            if $0.status.sortOrder != $1.status.sortOrder {
                return $0.status.sortOrder < $1.status.sortOrder
            }
            return $0.lastActivityAt > $1.lastActivityAt
        }
    }

    @discardableResult
    mutating func apply(_ update: SourceUpdate) -> Bool {
        guard !processedEventIdSet.contains(update.event.eventId) else { return false }
        remember(update.event.eventId)

        let id = "\(update.event.source.kind):\(update.local.externalTaskId)"
        let previous = tasksById[id]
        var status = update.event.status
        var viewedAt = previous?.lastViewedAt

        if status == .running || status == .needsAttention {
            viewedAt = nil
        } else if status == .inactive,
                  previous?.status == .awaitingReview,
                  previous?.completedAt == update.local.completedAt,
                  viewedAt == nil {
            // Once a completion has surfaced, it remains unread until the user opens it.
            status = .awaitingReview
        } else if status == .awaitingReview,
                  let viewedAt,
                  let completedAt = update.local.completedAt,
                  viewedAt >= completedAt {
            status = .inactive
        }

        let task = MonitoredTask(
            id: id,
            externalTaskId: update.local.externalTaskId,
            sourceKind: update.event.source.kind,
            title: update.local.displayTitle,
            summary: update.event.summary,
            status: status,
            priority: update.event.priority,
            projectName: update.local.projectName,
            workspaceDisplayPath: update.local.workspaceDisplayPath,
            branch: update.local.branch,
            model: update.local.model,
            currentAction: update.local.currentAction,
            startedAt: update.local.startedAt,
            lastActivityAt: update.event.occurredAt,
            completedAt: update.local.completedAt,
            lastViewedAt: viewedAt,
            durationMs: update.event.durationMs,
            deepLink: update.local.deepLink
        )
        tasksById[id] = task
        return task != previous
    }

    @discardableResult
    mutating func markViewed(taskId: String, at date: Date = Date()) -> Bool {
        guard var task = tasksById[taskId] else { return false }
        task.lastViewedAt = date
        if task.status == .awaitingReview { task.status = .inactive }
        tasksById[taskId] = task
        return true
    }

    func persistedState() -> PersistedMonitorState {
        PersistedMonitorState(tasks: tasks, processedEventIds: processedEventIds)
    }

    @discardableResult
    mutating func reconcile(sourceKind: String, externalTaskIds: Set<String>) -> Bool {
        let staleIds = tasksById.values.compactMap { task in
            task.sourceKind == sourceKind && !externalTaskIds.contains(task.externalTaskId)
                ? task.id
                : nil
        }
        staleIds.forEach { tasksById.removeValue(forKey: $0) }
        return !staleIds.isEmpty
    }

    private mutating func remember(_ eventId: String) {
        processedEventIdSet.insert(eventId)
        processedEventIds.append(eventId)
        if processedEventIds.count > eventHistoryLimit {
            let overflow = processedEventIds.count - eventHistoryLimit
            let removed = Array(processedEventIds.prefix(overflow))
            processedEventIds.removeFirst(overflow)
            removed.forEach { processedEventIdSet.remove($0) }
        }
    }
}

private extension MonitorTaskStatus {
    var sortOrder: Int {
        switch self {
        case .needsAttention: 0
        case .running: 1
        case .awaitingReview: 2
        case .inactive: 3
        }
    }
}
