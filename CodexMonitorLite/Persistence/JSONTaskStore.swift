import Foundation

struct JSONTaskStore {
    let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.fileURL = root
                .appendingPathComponent("CodexMonitorLite", isDirectory: true)
                .appendingPathComponent("state.json", isDirectory: false)
        }
    }

    func load() throws -> PersistedMonitorState {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .empty }
        return try EventTime.decoder().decode(PersistedMonitorState.self, from: Data(contentsOf: fileURL))
    }

    func save(_ state: PersistedMonitorState) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try EventTime.encoder(prettyPrinted: true).encode(state)
        try data.write(to: fileURL, options: [.atomic])
    }
}
