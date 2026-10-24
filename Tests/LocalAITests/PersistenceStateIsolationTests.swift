import XCTest
@testable import LocalAI

final class PersistenceStateIsolationTests: XCTestCase {
    private var tempDir: URL!
    private var storeURL: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PersistenceIsolationTests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        storeURL = tempDir.appendingPathComponent("studio-state.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Per-workspace settings isolation

    func testWorkspacePermissionsAreIsolated() throws {
        let store = StudioPersistenceStore(fileURL: storeURL)
        let snapshot = StudioPersistenceSnapshot(
            workspacePermissions: [
                "/workspace/A": WorkspacePermissions(read: true, write: true, delete: false, shell: false, network: false, tools: false),
                "/workspace/B": WorkspacePermissions(read: true, write: false, delete: false, shell: false, network: false, tools: false)
            ]
        )
        store.save(snapshot)

        let loaded = store.load()
        XCTAssertEqual(loaded.workspacePermissions["/workspace/A"]?.write, true)
        XCTAssertEqual(loaded.workspacePermissions["/workspace/B"]?.write, false)
    }

    func testWorkspaceNameOverridesAreIsolated() throws {
        let store = StudioPersistenceStore(fileURL: storeURL)
        let snapshot = StudioPersistenceSnapshot(
            workspaceNameOverrides: [
                "/workspace/A": "Project Alpha",
                "/workspace/B": "Project Beta"
            ]
        )
        store.save(snapshot)

        let loaded = store.load()
        XCTAssertEqual(loaded.workspaceNameOverrides["/workspace/A"], "Project Alpha")
        XCTAssertEqual(loaded.workspaceNameOverrides["/workspace/B"], "Project Beta")
    }

    func testWorkspaceMCPSettingsAreIsolated() throws {
        let serverA = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let serverB = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

        let store = StudioPersistenceStore(fileURL: storeURL)
        let snapshot = StudioPersistenceSnapshot(
            workspaceMCPSettings: [
                "/workspace/A": WorkspaceMCPSettings(enabledServerIDs: [serverA]),
                "/workspace/B": WorkspaceMCPSettings(enabledServerIDs: [serverB])
            ]
        )
        store.save(snapshot)

        let loaded = store.load()
        XCTAssertEqual(loaded.workspaceMCPSettings["/workspace/A"]?.enabledServerIDs, [serverA])
        XCTAssertEqual(loaded.workspaceMCPSettings["/workspace/B"]?.enabledServerIDs, [serverB])
    }

    // MARK: - Chat history tied to correct context

    func testChatThreadsAreIsolatedByContextKey() throws {
        let store = StudioPersistenceStore(fileURL: storeURL)
        let snapshot = StudioPersistenceSnapshot(
            chatThreads: [
                ChatThread(contextKey: "workspace:/path/A", title: "Workspace A Chat"),
                ChatThread(contextKey: "workspace:/path/B", title: "Workspace B Chat"),
                ChatThread(contextKey: "general", title: "General Chat")
            ]
        )
        store.save(snapshot)

        let loaded = store.load()
        let workspaceA = loaded.chatThreads.filter { $0.contextKey == "workspace:/path/A" }
        let workspaceB = loaded.chatThreads.filter { $0.contextKey == "workspace:/path/B" }
        let general = loaded.chatThreads.filter { $0.contextKey == "general" }

        XCTAssertEqual(workspaceA.count, 1)
        XCTAssertEqual(workspaceB.count, 1)
        XCTAssertEqual(general.count, 1)
        XCTAssertEqual(workspaceA.first?.title, "Workspace A Chat")
    }

    func testChatThreadsWithSameContextKeyGroupTogether() throws {
        let store = StudioPersistenceStore(fileURL: storeURL)
        let snapshot = StudioPersistenceSnapshot(
            chatThreads: [
                ChatThread(contextKey: "workspace:/path/A", title: "Thread 1"),
                ChatThread(contextKey: "workspace:/path/A", title: "Thread 2")
            ]
        )
        store.save(snapshot)

        let loaded = store.load()
        let workspaceAThreads = loaded.chatThreads.filter { $0.contextKey == "workspace:/path/A" }
        XCTAssertEqual(workspaceAThreads.count, 2)
    }

    // MARK: - Saved responses deduplication

    func testSavedResponseDedupBySourceMessageID() async throws {
        let storeURL = self.storeURL
        let appState = await MainActor.run {
            AppState(persistenceStore: StudioPersistenceStore(fileURL: storeURL))
        }
        let messageID = UUID()

        let msg1 = ChatMessage(id: messageID, role: .assistant, markdown: "Response")
        let msg2 = ChatMessage(id: messageID, role: .assistant, markdown: "Response")

        let saved1 = await MainActor.run { appState.saveChatMessage(msg1) }
        let saved2 = await MainActor.run { appState.saveChatMessage(msg2) }

        XCTAssertTrue(saved1)
        XCTAssertFalse(saved2, "Duplicate save of same message should be rejected")
        let count = await MainActor.run { appState.savedResponses.count }
        XCTAssertEqual(count, 1)
    }

    func testSavedResponseWithDifferentSourceIDsBothSaved() async throws {
        let storeURL = self.storeURL
        let appState = await MainActor.run {
            AppState(persistenceStore: StudioPersistenceStore(fileURL: storeURL))
        }
        let msg1 = ChatMessage(role: .assistant, markdown: "Response A")
        let msg2 = ChatMessage(role: .assistant, markdown: "Response B")

        let saved1 = await MainActor.run { appState.saveChatMessage(msg1) }
        let saved2 = await MainActor.run { appState.saveChatMessage(msg2) }

        XCTAssertTrue(saved1)
        XCTAssertTrue(saved2)
        let count = await MainActor.run { appState.savedResponses.count }
        XCTAssertEqual(count, 2)
    }

    func testSavedResponseWithNilSourceIDAlwaysSaves() async throws {
        let storeURL = self.storeURL
        let appState = await MainActor.run {
            AppState(persistenceStore: StudioPersistenceStore(fileURL: storeURL))
        }
        let msg1 = ChatMessage(role: .assistant, markdown: "Response A")
        let msg2 = ChatMessage(role: .assistant, markdown: "Response B")

        let saved1 = await MainActor.run { appState.saveChatMessage(msg1) }
        let saved2 = await MainActor.run { appState.saveChatMessage(msg2) }

        XCTAssertTrue(saved1)
        XCTAssertTrue(saved2)
        let count = await MainActor.run { appState.savedResponses.count }
        XCTAssertEqual(count, 2)
    }

    func testSavedResponseDedupIsContextScoped() async throws {
        let storeURL = self.storeURL
        let appState = await MainActor.run {
            AppState(persistenceStore: StudioPersistenceStore(fileURL: storeURL))
        }
        let messageID = UUID()
        let msg1 = ChatMessage(id: messageID, role: .assistant, markdown: "Response")

        let saved1 = await MainActor.run { appState.saveChatMessage(msg1) }

        XCTAssertTrue(saved1)
        let count = await MainActor.run { appState.savedResponses.count }
        XCTAssertEqual(count, 1)
        let savedResponse = await MainActor.run { appState.savedResponses.first }
        XCTAssertEqual(savedResponse?.sourceMessageID, messageID)
    }

    // MARK: - Saved responses filtered by context

    func testCurrentSavedResponsesFilteredByContextKey() throws {
        let store = StudioPersistenceStore(fileURL: storeURL)
        let snapshot = StudioPersistenceSnapshot(
            savedResponses: [
                SavedResponse(contextKey: "workspace:/path/A", title: "Saved A", markdown: "Content A", kind: .tool),
                SavedResponse(contextKey: "workspace:/path/B", title: "Saved B", markdown: "Content B", kind: .chat),
                SavedResponse(contextKey: "general", title: "Saved General", markdown: "General", kind: .chat)
            ]
        )
        store.save(snapshot)

        let loaded = store.load()
        let workspaceAResponses = loaded.savedResponses.filter { $0.contextKey == "workspace:/path/A" }
        XCTAssertEqual(workspaceAResponses.count, 1)
        XCTAssertEqual(workspaceAResponses.first?.title, "Saved A")
    }

    // MARK: - Tasks by context isolation

    func testTasksByContextAreIsolated() throws {
        let store = StudioPersistenceStore(fileURL: storeURL)
        let snapshot = StudioPersistenceSnapshot(
            tasksByContext: [
                "workspace:/path/A": [
                    StudioTask(title: "Task A", prompt: "Prompt A", outputMode: .markdown, status: .complete, plan: [], activity: [])
                ],
                "workspace:/path/B": [
                    StudioTask(title: "Task B", prompt: "Prompt B", outputMode: .markdown, status: .complete, plan: [], activity: [])
                ]
            ]
        )
        store.save(snapshot)

        let loaded = store.load()
        XCTAssertEqual(loaded.tasksByContext["workspace:/path/A"]?.count, 1)
        XCTAssertEqual(loaded.tasksByContext["workspace:/path/B"]?.count, 1)
        XCTAssertEqual(loaded.tasksByContext["workspace:/path/A"]?.first?.title, "Task A")
        XCTAssertEqual(loaded.tasksByContext["workspace:/path/B"]?.first?.title, "Task B")
    }

    func testCurrentSavedResponsesAreContextScoped() async throws {
        let storeURL = self.storeURL
        let appState = await MainActor.run {
            AppState(persistenceStore: StudioPersistenceStore(fileURL: storeURL))
        }
        let workspacePath = "/workspace/A"
        let workspace = Workspace(url: URL(fileURLWithPath: workspacePath), kind: .code, files: [], summary: WorkspaceSummary(), scannedAt: Date())

        await MainActor.run {
            appState.savedResponses = [
                SavedResponse(contextKey: "general", title: "General", markdown: "General content", kind: .chat),
                SavedResponse(contextKey: "workspace:\(workspacePath)", title: "Workspace", markdown: "Workspace content", kind: .chat),
                SavedResponse(contextKey: "workspace:/workspace/B", title: "Other", markdown: "Other content", kind: .chat)
            ]
            appState.mode = .workspace
            appState.workspace = workspace
        }

        let current = await MainActor.run { appState.currentSavedResponses }
        XCTAssertEqual(current.count, 1)
        XCTAssertEqual(current.first?.title, "Workspace")
    }

    func testWorkspaceSettingsArePathScopedAndPersisted() async throws {
        let storeURL = self.storeURL
        let appState = await MainActor.run {
            AppState(persistenceStore: StudioPersistenceStore(fileURL: storeURL))
        }
        let pathA = "/workspace/A"
        let pathB = "/workspace/B"
        let serverA = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let serverB = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!

        await MainActor.run {
            appState.saveWorkspaceDisplayName("Alpha", path: pathA)
            appState.savePermissions(.safeAutomation, for: pathA)
            appState.setMCPServerEnabledInWorkspace(true, serverID: serverA, path: pathA)
            appState.setMCPServerEnabledInWorkspace(true, serverID: serverB, path: pathB)
        }

        let displayA = await MainActor.run { appState.workspaceDisplayName(for: pathA, fallback: "Fallback") }
        let permsA = await MainActor.run { appState.permissions(for: pathA) }
        let enabledA = await MainActor.run { appState.isMCPServerEnabledInWorkspace(serverA, path: pathA) }
        let enabledB = await MainActor.run { appState.isMCPServerEnabledInWorkspace(serverB, path: pathB) }
        let disabledForOther = await MainActor.run { appState.isMCPServerEnabledInWorkspace(serverA, path: pathB) }

        XCTAssertEqual(displayA, "Alpha")
        XCTAssertEqual(permsA, .safeAutomation)
        XCTAssertTrue(enabledA)
        XCTAssertTrue(enabledB)
        XCTAssertFalse(disabledForOther)
    }

    // MARK: - Migration from legacy container

    func testMigrationLegacyToCurrentContainer() throws {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let legacyDir = appSupport.appendingPathComponent("LocalFMStudio", isDirectory: true)
        let currentDir = appSupport.appendingPathComponent(AppSupport.directoryName, isDirectory: true)

        try? FileManager.default.removeItem(at: legacyDir)
        try? FileManager.default.removeItem(at: currentDir)

        try FileManager.default.createDirectory(at: legacyDir, withIntermediateDirectories: true)
        try "legacy data".write(to: legacyDir.appendingPathComponent("state.json"), atomically: true, encoding: .utf8)

        AppSupport.migrateLegacyContainer()

        XCTAssertTrue(FileManager.default.fileExists(atPath: currentDir.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: currentDir.appendingPathComponent("state.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyDir.path), "Legacy container should be moved")

        try? FileManager.default.removeItem(at: currentDir)
    }

    func testMigrationDoesNothingWhenCurrentExists() throws {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let legacyDir = appSupport.appendingPathComponent("LocalFMStudio", isDirectory: true)
        let currentDir = appSupport.appendingPathComponent(AppSupport.directoryName, isDirectory: true)

        try? FileManager.default.removeItem(at: legacyDir)
        try? FileManager.default.removeItem(at: currentDir)
        try FileManager.default.createDirectory(at: legacyDir, withIntermediateDirectories: true)
        try "legacy".write(to: legacyDir.appendingPathComponent("legacy.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: currentDir, withIntermediateDirectories: true)
        try "current".write(to: currentDir.appendingPathComponent("current.txt"), atomically: true, encoding: .utf8)

        AppSupport.migrateLegacyContainer()

        XCTAssertTrue(FileManager.default.fileExists(atPath: currentDir.appendingPathComponent("current.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyDir.path), "Legacy should not be moved when current exists")

        try? FileManager.default.removeItem(at: legacyDir)
        try? FileManager.default.removeItem(at: currentDir)
    }
}
