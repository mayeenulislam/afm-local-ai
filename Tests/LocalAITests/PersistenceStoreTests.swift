import XCTest
@testable import LocalAI

final class TaskHistoryStoreTests: XCTestCase {
    private var tempDir: URL!
    private var storeURL: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TaskHistoryTests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        storeURL = tempDir.appendingPathComponent("task-history.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testLoadMissingFileReturnsEmpty() {
        let store = TaskHistoryStore(fileURL: storeURL)
        let tasks = store.load()
        XCTAssertTrue(tasks.isEmpty)
    }

    func testLoadCorruptJSONReturnsEmpty() throws {
        // A corrupt/partially-written state file must not crash the app or surface
        // garbage: decode failure degrades to an empty history (LAUNCH-006).
        try "definitely {{{ not json".write(to: storeURL, atomically: true, encoding: .utf8)
        let store = TaskHistoryStore(fileURL: storeURL)
        let tasks = store.load()
        XCTAssertTrue(tasks.isEmpty)
    }

    func testSaveAndLoadRoundTrip() {
        let store = TaskHistoryStore(fileURL: storeURL)
        let task = StudioTask(
            id: UUID(uuidString: "12345678-1234-1234-1234-123456789abc")!,
            title: "Test Task",
            prompt: "Do something",
            outputMode: .markdown,
            status: .complete,
            plan: ["Step 1", "Step 2"],
            activity: [ActivityEvent(title: "Done", detail: "Finished", state: .done)],
            resultMarkdown: "Result here"
        )

        store.save([task])
        let loaded = store.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].title, "Test Task")
        XCTAssertEqual(loaded[0].prompt, "Do something")
        XCTAssertEqual(loaded[0].status, .complete)
        XCTAssertEqual(loaded[0].plan, ["Step 1", "Step 2"])
        XCTAssertEqual(loaded[0].resultMarkdown, "Result here")
        XCTAssertEqual(loaded[0].activity.count, 1)
    }

    func testSaveOverwritesPreviousData() {
        let store = TaskHistoryStore(fileURL: storeURL)

        let task1 = StudioTask(title: "First", prompt: "One", outputMode: .markdown, status: .complete, plan: [], activity: [], resultMarkdown: "First result")
        store.save([task1])

        let task2 = StudioTask(title: "Second", prompt: "Two", outputMode: .markdown, status: .complete, plan: [], activity: [], resultMarkdown: "Second result")
        store.save([task2])

        let loaded = store.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].title, "Second")
    }

    func testSaveEmptyArrayOverwritesWithEmpty() {
        let store = TaskHistoryStore(fileURL: storeURL)
        let task = StudioTask(title: "Test", prompt: "test", outputMode: .markdown, status: .complete, plan: [], activity: [], resultMarkdown: nil)
        store.save([task])
        store.save([])
        let loaded = store.load()
        XCTAssertTrue(loaded.isEmpty)
    }

    func testStoreWithDefaultURL() {
        let store = TaskHistoryStore()
        let loaded = store.load()
        XCTAssertTrue(loaded is [StudioTask])
    }
}

final class StudioPersistenceStoreTests: XCTestCase {
    private var tempDir: URL!
    private var storeURL: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("StudioPersistenceTests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        storeURL = tempDir.appendingPathComponent("studio-state.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testLoadMissingFileReturnsDefaultSnapshot() {
        let store = StudioPersistenceStore(fileURL: storeURL)
        let snapshot = store.load()
        XCTAssertTrue(snapshot.recentWorkspaces.isEmpty)
        XCTAssertTrue(snapshot.chatThreads.isEmpty)
        XCTAssertTrue(snapshot.savedResponses.isEmpty)
        XCTAssertTrue(snapshot.tasksByContext.isEmpty)
        XCTAssertTrue(snapshot.mcpServers.isEmpty)
    }

    func testLoadCorruptJSONReturnsDefaultSnapshot() throws {
        // Corrupt persisted state degrades to a pristine snapshot instead of
        // crashing or resurrecting half-decoded fields (LAUNCH-006).
        try "{ not valid json, file: [".write(to: storeURL, atomically: true, encoding: .utf8)
        let store = StudioPersistenceStore(fileURL: storeURL)
        let snapshot = store.load()
        XCTAssertTrue(snapshot.recentWorkspaces.isEmpty)
        XCTAssertTrue(snapshot.chatThreads.isEmpty)
        XCTAssertTrue(snapshot.savedResponses.isEmpty)
        XCTAssertTrue(snapshot.tasksByContext.isEmpty)
        XCTAssertTrue(snapshot.mcpServers.isEmpty)
        XCTAssertTrue(snapshot.workspacePermissions.isEmpty)
        XCTAssertTrue(snapshot.workspaceMCPSettings.isEmpty)
        XCTAssertTrue(snapshot.workspaceNameOverrides.isEmpty)
    }

    func testSaveAndLoadRoundTrip() {
        let store = StudioPersistenceStore(fileURL: storeURL)

        let snapshot = StudioPersistenceSnapshot(
            recentWorkspaces: [
                RecentWorkspace(name: "MyProject", path: "/tmp/MyProject", kind: .code, openedAt: Date(timeIntervalSince1970: 1000), totalFiles: 42)
            ],
            chatThreads: [
                ChatThread(contextKey: "general", title: "Test Chat")
            ],
            savedResponses: [
                SavedResponse(contextKey: "general", title: "Saved", markdown: "Content", kind: .chat)
            ],
            tasksByContext: ["general": [StudioTask(title: "Task", prompt: "Prompt", outputMode: .markdown, status: .complete, plan: [], activity: [])]],
            mcpServers: [
                MCPServerConfig(name: "Server1", transport: .stdio, command: "run", arguments: "arg1")
            ],
            workspaceMCPSettings: ["path1": WorkspaceMCPSettings(enabledServerIDs: [UUID()])],
            workspaceNameOverrides: ["path1": "Custom Name"],
            workspacePermissions: ["path1": WorkspacePermissions.safeAutomation]
        )

        store.save(snapshot)
        let loaded = store.load()

        XCTAssertEqual(loaded.recentWorkspaces.count, 1)
        XCTAssertEqual(loaded.recentWorkspaces[0].name, "MyProject")
        XCTAssertEqual(loaded.recentWorkspaces[0].totalFiles, 42)

        XCTAssertEqual(loaded.chatThreads.count, 1)
        XCTAssertEqual(loaded.chatThreads[0].title, "Test Chat")

        XCTAssertEqual(loaded.savedResponses.count, 1)
        XCTAssertEqual(loaded.savedResponses[0].title, "Saved")

        XCTAssertEqual(loaded.tasksByContext.count, 1)
        XCTAssertEqual(loaded.tasksByContext["general"]?.count, 1)

        XCTAssertEqual(loaded.mcpServers.count, 1)
        XCTAssertEqual(loaded.mcpServers[0].name, "Server1")
        XCTAssertEqual(loaded.mcpServers[0].command, "run")

        XCTAssertEqual(loaded.workspaceMCPSettings.count, 1)
        XCTAssertEqual(loaded.workspaceNameOverrides.count, 1)
        XCTAssertEqual(loaded.workspacePermissions.count, 1)
    }

    func testSaveCreatesParentDirectory() {
        let nestedURL = tempDir.appendingPathComponent("nested/dir").appendingPathComponent("studio-state.json")
        let store = StudioPersistenceStore(fileURL: nestedURL)
        store.save(StudioPersistenceSnapshot())

        XCTAssertTrue(FileManager.default.fileExists(atPath: nestedURL.path))
    }

    func testMCPHeaderSecretsAreNotPersistedInPlaintext() throws {
        let secrets = InMemorySecretStore()
        let store = StudioPersistenceStore(fileURL: storeURL, secretStore: secrets)
        let server = MCPServerConfig(
            name: "Remote",
            transport: .streamableHTTP,
            url: "https://api.example.com/mcp",
            headers: ["Authorization": "Bearer super-secret-token"]
        )

        store.save(StudioPersistenceSnapshot(mcpServers: [server]))

        let raw = try String(contentsOf: storeURL, encoding: .utf8)
        XCTAssertFalse(raw.contains("super-secret-token"), "MCP header values must not be written to the state file in plaintext")
        XCTAssertNotNil(secrets.value(for: "mcp-server-\(server.id.uuidString)"))

        let loaded = store.load()
        XCTAssertEqual(loaded.mcpServers.first?.headers["Authorization"], "Bearer super-secret-token")
    }

    func testRemovingMCPServerDeletesItsStoredSecrets() {
        let secrets = InMemorySecretStore()
        let store = StudioPersistenceStore(fileURL: storeURL, secretStore: secrets)
        let server = MCPServerConfig(
            name: "Remote",
            transport: .streamableHTTP,
            url: "https://api.example.com/mcp",
            headers: ["Authorization": "Bearer super-secret-token"]
        )
        store.save(StudioPersistenceSnapshot(mcpServers: [server]))
        XCTAssertNotNil(secrets.value(for: "mcp-server-\(server.id.uuidString)"))

        store.save(StudioPersistenceSnapshot(mcpServers: []))
        XCTAssertNil(secrets.value(for: "mcp-server-\(server.id.uuidString)"), "Deleting a server must remove its stored secrets")
    }
}
