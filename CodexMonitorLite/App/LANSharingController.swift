import Combine
import Foundation
import Network

struct LANTaskItem: Codable, Equatable {
    let id: String
    let source: String
    let title: String
    let project: String
    let status: String
    let lastActivityAt: String
    let durationMs: Int64?

    init(task: MonitoredTask, now: Date = Date()) {
        id = task.id
        source = task.sourceKind
        title = task.title
        project = task.projectName
        status = task.status.rawValue
        lastActivityAt = EventTime.rfc3339Milliseconds(task.lastActivityAt)
        durationMs = task.elapsedMilliseconds(at: now)
    }
}

struct LANTaskSnapshot: Codable, Equatable {
    static let schemaVersion = 1

    let type: String
    let schemaVersion: Int
    let revision: String
    let generatedAt: String
    let tasks: [LANTaskItem]

    init(tasks: [MonitoredTask], now: Date = Date(), revision: String = UUID().uuidString) {
        type = "snapshot"
        schemaVersion = Self.schemaVersion
        self.revision = revision
        generatedAt = EventTime.rfc3339Milliseconds(now)
        self.tasks = tasks
            .filter(\.status.isActive)
            .map { LANTaskItem(task: $0, now: now) }
    }

    func encodedLine() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var data = try encoder.encode(self)
        data.append(0x0A)
        return data
    }
}

private struct LANAuthenticationRequest: Decodable {
    let type: String
    let pairingCode: String
}

private enum LANTaskServerStatus {
    case starting
    case ready(port: UInt16, connectedDevices: Int)
    case failed(String)
}

@MainActor
final class LANSharingController: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var statusText = "已关闭"
    @Published private(set) var connectedDeviceCount = 0
    @Published private(set) var pairingCode: String

    private let defaults: UserDefaults
    private let persistenceEnabled: Bool
    private var server: LANTaskServer?
    private var latestTasks: [MonitoredTask] = []
    private var generation = 0

    private static let enabledKey = "CodexMonitorLite.lanSharingEnabled"
    private static let pairingCodeKey = "CodexMonitorLite.lanPairingCode"

    init(defaults: UserDefaults = .standard, persistenceEnabled: Bool = true) {
        self.defaults = defaults
        self.persistenceEnabled = persistenceEnabled

        if persistenceEnabled,
           let savedCode = defaults.string(forKey: Self.pairingCodeKey),
           !savedCode.isEmpty {
            pairingCode = savedCode
        } else {
            pairingCode = Self.makePairingCode()
            if persistenceEnabled {
                defaults.set(pairingCode, forKey: Self.pairingCodeKey)
            }
        }

        if persistenceEnabled, defaults.bool(forKey: Self.enabledKey) {
            setEnabled(true)
        }
    }

    var statusColor: MonitorConnectionColor {
        guard isEnabled else { return .inactive }
        if statusText.hasPrefix("无法") { return .failed }
        return connectedDeviceCount > 0 ? .connected : .waiting
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled || (enabled && server == nil) else { return }
        generation += 1
        let currentGeneration = generation

        if enabled {
            isEnabled = true
            connectedDeviceCount = 0
            statusText = "正在启动"

            let newServer = LANTaskServer(pairingCode: normalizedPairingCode) { [weak self] status in
                DispatchQueue.main.async {
                    guard let self, self.generation == currentGeneration else { return }
                    self.apply(status)
                }
            }
            server = newServer
            newServer.update(tasks: latestTasks)
            do {
                try newServer.start()
            } catch {
                server = nil
                statusText = "无法启动：\(error.localizedDescription)"
            }
        } else {
            isEnabled = false
            connectedDeviceCount = 0
            statusText = "已关闭"
            server?.stop()
            server = nil
        }

        if persistenceEnabled {
            defaults.set(isEnabled, forKey: Self.enabledKey)
        }
    }

    func update(tasks: [MonitoredTask]) {
        latestTasks = tasks
        server?.update(tasks: tasks)
    }

    func regeneratePairingCode() {
        pairingCode = Self.makePairingCode()
        if persistenceEnabled {
            defaults.set(pairingCode, forKey: Self.pairingCodeKey)
        }
        if isEnabled {
            setEnabled(false)
            setEnabled(true)
        }
    }

    func stopForTermination() {
        generation += 1
        server?.stop()
        server = nil
    }

    private var normalizedPairingCode: String {
        pairingCode.replacingOccurrences(of: "-", with: "").uppercased()
    }

    private func apply(_ status: LANTaskServerStatus) {
        switch status {
        case .starting:
            statusText = "正在启动"
            connectedDeviceCount = 0
        case .ready(_, let connectedDevices):
            connectedDeviceCount = connectedDevices
            statusText = connectedDevices == 0 ? "等待手机连接" : "已连接 \(connectedDevices) 台设备"
        case .failed(let message):
            statusText = "无法共享：\(message)"
            connectedDeviceCount = 0
        }
    }

    private static func makePairingCode() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        var generator = SystemRandomNumberGenerator()
        let raw = String((0..<10).map { _ in alphabet.randomElement(using: &generator)! })
        let split = raw.index(raw.startIndex, offsetBy: 5)
        return "\(raw[..<split])-\(raw[split...])"
    }
}

enum MonitorConnectionColor {
    case inactive
    case waiting
    case connected
    case failed
}

private final class LANTaskServer {
    private final class Client {
        let id = UUID()
        let connection: NWConnection
        var buffer = Data()
        var isAuthenticated = false

        init(connection: NWConnection) {
            self.connection = connection
        }
    }

    private let queue = DispatchQueue(label: "com.yzgus.codex-monitor-lite.lan")
    private let pairingCode: String
    private let statusHandler: (LANTaskServerStatus) -> Void
    private var listener: NWListener?
    private var clients: [UUID: Client] = [:]
    private var latestSnapshot = Data()
    private var readyPort: UInt16?

    init(pairingCode: String, statusHandler: @escaping (LANTaskServerStatus) -> Void) {
        self.pairingCode = pairingCode
        self.statusHandler = statusHandler
    }

    func start() throws {
        statusHandler(.starting)
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters, on: .any)
        listener.service = NWListener.Service(
            name: Host.current().localizedName ?? "Codex Monitor",
            type: "_codexmonitor._tcp"
        )
        listener.stateUpdateHandler = { [weak self] state in
            self?.handle(listenerState: state)
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        self.listener = listener
        listener.start(queue: queue)
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            listener?.cancel()
            listener = nil
            clients.values.forEach { $0.connection.cancel() }
            clients.removeAll()
            readyPort = nil
        }
    }

    func update(tasks: [MonitoredTask]) {
        let snapshot = LANTaskSnapshot(tasks: tasks)
        guard let payload = try? snapshot.encodedLine() else { return }
        queue.async { [weak self] in
            guard let self else { return }
            latestSnapshot = payload
            clients.values
                .filter(\.isAuthenticated)
                .forEach { self.send(payload, to: $0) }
        }
    }

    private func handle(listenerState: NWListener.State) {
        switch listenerState {
        case .ready:
            readyPort = listener?.port?.rawValue
            reportReady()
        case .failed(let error):
            statusHandler(.failed(error.localizedDescription))
        case .cancelled:
            readyPort = nil
        default:
            break
        }
    }

    private func accept(_ connection: NWConnection) {
        let client = Client(connection: connection)
        clients[client.id] = client
        connection.stateUpdateHandler = { [weak self, weak client] state in
            guard let self, let client else { return }
            switch state {
            case .failed, .cancelled:
                remove(client)
            default:
                break
            }
        }
        connection.start(queue: queue)
        receive(from: client)
    }

    private func receive(from client: Client) {
        client.connection.receive(minimumIncompleteLength: 1, maximumLength: 4_096) { [weak self, weak client] data, _, isComplete, error in
            guard let self, let client else { return }
            if let data, !data.isEmpty {
                client.buffer.append(data)
                processBufferedLine(from: client)
            }

            if isComplete || error != nil {
                remove(client)
            } else {
                receive(from: client)
            }
        }
    }

    private func processBufferedLine(from client: Client) {
        guard !client.isAuthenticated else {
            client.buffer.removeAll(keepingCapacity: true)
            return
        }
        guard client.buffer.count <= 1_024 else {
            client.connection.cancel()
            return
        }
        guard let newline = client.buffer.firstIndex(of: 0x0A) else { return }

        let line = client.buffer[..<newline]
        client.buffer.removeSubrange(...newline)
        guard let request = try? JSONDecoder().decode(LANAuthenticationRequest.self, from: Data(line)),
              request.type == "authenticate",
              normalize(request.pairingCode) == pairingCode else {
            client.connection.cancel()
            return
        }

        client.isAuthenticated = true
        send(latestSnapshot, to: client)
        reportReady()
    }

    private func send(_ payload: Data, to client: Client) {
        guard !payload.isEmpty else { return }
        client.connection.send(content: payload, completion: .contentProcessed { [weak self, weak client] error in
            if error != nil, let self, let client {
                remove(client)
            }
        })
    }

    private func remove(_ client: Client) {
        let wasAuthenticated = client.isAuthenticated
        clients.removeValue(forKey: client.id)
        client.connection.cancel()
        if wasAuthenticated { reportReady() }
    }

    private func reportReady() {
        guard let readyPort else { return }
        let count = clients.values.filter(\.isAuthenticated).count
        statusHandler(.ready(port: readyPort, connectedDevices: count))
    }

    private func normalize(_ code: String) -> String {
        code
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
            .uppercased()
    }
}
