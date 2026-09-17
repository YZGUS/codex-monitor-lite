import AppKit
import Foundation

@MainActor
final class MonitorViewModel: ObservableObject {
    @Published var selectedFilter: MonitorFilter = .all
    @Published var onlyActive = false
    @Published private(set) var tasks: [MonitoredTask] = []
    @Published private(set) var connectionState: SourceConnectionState = .connecting

    private let adapter: any SourceAdapter
    private let publisher: any EventPublisher
    private let store: JSONTaskStore
    private var reducer: EventReducer
    private var sourceTask: Task<Void, Never>?
    private var sourceGeneration = 0

    init(
        adapter: any SourceAdapter,
        publisher: any EventPublisher = NoopEventPublisher(),
        store: JSONTaskStore = JSONTaskStore()
    ) {
        self.adapter = adapter
        self.publisher = publisher
        self.store = store
        let persisted = (try? store.load()) ?? .empty
        self.reducer = EventReducer(state: persisted)
        self.tasks = reducer.tasks
    }

    var visibleTasks: [MonitoredTask] {
        scopedTasks.filter(selectedFilter.includes)
    }

    func count(for filter: MonitorFilter) -> Int {
        scopedTasks.filter(filter.includes).count
    }

    var scopedTaskCount: Int { scopedTasks.count }

    func start() {
        guard sourceTask == nil else { return }
        connectionState = .connecting
        sourceGeneration += 1
        let generation = sourceGeneration
        sourceTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await message in adapter.makeStream() {
                    if Task.isCancelled { break }
                    switch message {
                    case .connected:
                        connectionState = .connected
                    case .update(let update):
                        if reducer.apply(update) {
                            tasks = reducer.tasks
                            try? store.save(reducer.persistedState())
                            // Remote delivery is optional and must never stop local monitoring.
                            try? await publisher.publish([update.event])
                        }
                    case .snapshot(let sourceKind, let externalTaskIds):
                        if reducer.reconcile(
                            sourceKind: sourceKind,
                            externalTaskIds: externalTaskIds
                        ) {
                            tasks = reducer.tasks
                            try? store.save(reducer.persistedState())
                        }
                    }
                }
            } catch {
                if !Task.isCancelled {
                    connectionState = .failed(error.localizedDescription)
                }
            }
            if sourceGeneration == generation { sourceTask = nil }
        }
    }

    func retry() {
        sourceGeneration += 1
        sourceTask?.cancel()
        sourceTask = nil
        start()
    }

    func open(_ task: MonitoredTask) {
        guard let deepLink = task.deepLink, NSWorkspace.shared.open(deepLink) else { return }
        if task.status == .awaitingReview {
            _ = reducer.markViewed(taskId: task.id)
            tasks = reducer.tasks
            try? store.save(reducer.persistedState())
        }
    }

    func stop() {
        sourceGeneration += 1
        sourceTask?.cancel()
        sourceTask = nil
    }

    private var scopedTasks: [MonitoredTask] {
        tasks.filter { !onlyActive || $0.status.isActive }
    }
}
