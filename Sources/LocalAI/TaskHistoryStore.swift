import Foundation

struct TaskHistoryStore {
    var fileURL: URL

    init(fileURL: URL? = nil) {
        let defaultURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(AppSupport.directoryName, isDirectory: true)
            .appendingPathComponent("task-history.json")
        self.fileURL = fileURL ?? defaultURL
    }

    func load() -> [StudioTask] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([StudioTask].self, from: data)) ?? []
    }

    func save(_ tasks: [StudioTask]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(tasks)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            AppSupport.secure(fileURL.deletingLastPathComponent(), isDirectory: true)
            AppSupport.secure(fileURL, isDirectory: false)
        } catch {
            // History persistence is best-effort; a failed save must not break task execution.
        }
    }
}

struct StudioPersistenceSnapshot: Codable {
    var recentWorkspaces: [RecentWorkspace] = []
    var chatThreads: [ChatThread] = []
    var savedResponses: [SavedResponse] = []
    var tasksByContext: [String: [StudioTask]] = [:]
    var mcpServers: [MCPServerConfig] = []
    var workspaceMCPSettings: [String: WorkspaceMCPSettings] = [:]
    var workspaceNameOverrides: [String: String] = [:]
    var workspacePermissions: [String: WorkspacePermissions] = [:]
}

struct StudioPersistenceStore {
    var fileURL: URL
    private let secretStore: SecretStoring

    init(fileURL: URL? = nil, secretStore: SecretStoring = InMemorySecretStore()) {
        let defaultURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(AppSupport.directoryName, isDirectory: true)
            .appendingPathComponent("studio-state.json")
        self.fileURL = fileURL ?? defaultURL
        self.secretStore = secretStore
    }

    private func secretKey(for serverID: UUID) -> String {
        "mcp-server-\(serverID.uuidString)"
    }

    private func persistedMCPServerIDs() -> Set<UUID> {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(StudioPersistenceSnapshot.self, from: data) else {
            return []
        }
        return Set(snapshot.mcpServers.map(\.id))
    }

    func load() -> StudioPersistenceSnapshot {
        guard let data = try? Data(contentsOf: fileURL) else { return StudioPersistenceSnapshot() }
        var snapshot = (try? JSONDecoder().decode(StudioPersistenceSnapshot.self, from: data)) ?? StudioPersistenceSnapshot()
        for index in snapshot.mcpServers.indices {
            let server = snapshot.mcpServers[index]
            guard server.headers.isEmpty,
                  let json = secretStore.value(for: secretKey(for: server.id)),
                  let headerData = json.data(using: .utf8),
                  let headers = try? JSONDecoder().decode([String: String].self, from: headerData) else { continue }
            snapshot.mcpServers[index].headers = headers
        }
        return snapshot
    }

    func save(_ snapshot: StudioPersistenceSnapshot) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var persisted = snapshot
        let liveIDs = Set(persisted.mcpServers.map(\.id))
        for index in persisted.mcpServers.indices {
            let server = persisted.mcpServers[index]
            guard !server.headers.isEmpty else { continue }
            if let headerData = try? JSONEncoder().encode(server.headers),
               let json = String(data: headerData, encoding: .utf8) {
                secretStore.set(json, for: secretKey(for: server.id))
            }
            // Header values live in the secret store, not the state file.
            persisted.mcpServers[index].headers = [:]
        }
        for removedID in persistedMCPServerIDs().subtracting(liveIDs) {
            secretStore.removeValue(for: secretKey(for: removedID))
        }
        do {
            let data = try encoder.encode(persisted)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            AppSupport.secure(fileURL.deletingLastPathComponent(), isDirectory: true)
            AppSupport.secure(fileURL, isDirectory: false)
        } catch {
            // App state persistence is best-effort; the workspace flow should continue.
        }
    }
}
