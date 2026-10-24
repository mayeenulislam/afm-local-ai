import XCTest
@testable import LocalAI

final class ModeSwitchingResetTests: XCTestCase {
    private var tempDir: URL!
    private var storeURL: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ModeSwitchingTests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        storeURL = tempDir.appendingPathComponent("state.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func createFiles(at relativePaths: [String], in dir: URL) throws {
        for path in relativePaths {
            let url = dir.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "content".write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func makeWorkspace(in dir: URL) -> Workspace {
        WorkspaceScanner().scan(url: dir)
    }

    // MARK: - showDashboard resets workspace state

    func testShowDashboardClearsWorkspaceState() async throws {
        let tempDir = self.tempDir!
        let storeURL = self.storeURL!
        let workspace = makeWorkspace(in: tempDir)
        let appState = await MainActor.run {
            AppState(persistenceStore: StudioPersistenceStore(fileURL: storeURL))
        }
        await MainActor.run {
            appState.workspace = workspace
            appState.selectedFilePaths = ["a.txt"]
            appState.expandedDirectories = ["sub"]
            appState.mode = .workspace
            appState.activeTemplate = appState.taskTemplates[0]
            appState.showDashboard()
        }

        let mode = await MainActor.run { appState.mode }
        let workspaceRef = await MainActor.run { appState.workspace }
        let selectedPaths = await MainActor.run { appState.selectedFilePaths }
        let expandedDirs = await MainActor.run { appState.expandedDirectories }
        let template = await MainActor.run { appState.activeTemplate }

        XCTAssertEqual(mode, .dashboard)
        XCTAssertNil(workspaceRef)
        XCTAssertTrue(selectedPaths.isEmpty)
        XCTAssertTrue(expandedDirs.isEmpty)
        XCTAssertNil(template)
    }

    // MARK: - startGeneralChat clears workspace context

    func testStartGeneralChatClearsWorkspaceContext() async throws {
        let tempDir = self.tempDir!
        let storeURL = self.storeURL!
        let workspace = makeWorkspace(in: tempDir)
        let appState = await MainActor.run {
            AppState(persistenceStore: StudioPersistenceStore(fileURL: storeURL))
        }
        await MainActor.run {
            appState.workspace = workspace
            appState.selectedFilePaths = ["a.txt"]
            appState.expandedDirectories = ["sub"]
            appState.startGeneralChat()
        }

        let mode = await MainActor.run { appState.mode }
        let workspaceRef = await MainActor.run { appState.workspace }
        let selectedPaths = await MainActor.run { appState.selectedFilePaths }
        let expandedDirs = await MainActor.run { appState.expandedDirectories }

        XCTAssertEqual(mode, .generalChat)
        XCTAssertNil(workspaceRef, "General chat should not have a workspace")
        XCTAssertTrue(selectedPaths.isEmpty, "General chat should not have checked files")
        XCTAssertTrue(expandedDirs.isEmpty)
    }

    // MARK: - loadWorkspace clears previous state

    func testLoadWorkspaceClearsPreviousCheckedFiles() async throws {
        let tempDir = self.tempDir!
        let storeURL = self.storeURL!
        try createFiles(at: ["a.txt", "b.txt", "sub/c.txt"], in: tempDir)

        let workspace = makeWorkspace(in: tempDir)
        let appState = await MainActor.run {
            AppState(persistenceStore: StudioPersistenceStore(fileURL: storeURL))
        }
        await MainActor.run {
            appState.workspace = workspace
            appState.selectedFilePaths = ["a.txt"]
            appState.expandedDirectories = ["sub"]
        }

        await MainActor.run {
            appState.loadWorkspace(tempDir)
        }

        let selectedPaths = await MainActor.run { appState.selectedFilePaths }
        XCTAssertTrue(selectedPaths.isEmpty, "Loading workspace should reset checked files to empty (opt-in)")
    }

    func testLoadWorkspaceEntersWorkspaceMode() async throws {
        let tempDir = self.tempDir!
        let storeURL = self.storeURL!
        let appState = await MainActor.run {
            AppState(persistenceStore: StudioPersistenceStore(fileURL: storeURL))
        }
        await MainActor.run {
            appState.mode = .dashboard
            appState.loadWorkspace(tempDir)
        }

        let mode = await MainActor.run { appState.mode }
        let workspaceRef = await MainActor.run { appState.workspace }
        XCTAssertEqual(mode, .workspace)
        XCTAssertNotNil(workspaceRef)
    }

    // MARK: - Workspace change resets context scope

    func testSwitchingWorkspacesResetsCheckedFilePaths() async throws {
        let tempDir = self.tempDir!
        let storeURL = self.storeURL!
        let oldWorkspace = tempDir.appendingPathComponent("old")
        let newWorkspace = tempDir.appendingPathComponent("new")
        try FileManager.default.createDirectory(at: oldWorkspace, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: newWorkspace, withIntermediateDirectories: true)
        try createFiles(at: ["a.txt", "b.txt"], in: oldWorkspace)
        try createFiles(at: ["c.txt", "d.txt"], in: newWorkspace)

        let oldWs = makeWorkspace(in: oldWorkspace)
        let appState = await MainActor.run {
            AppState(persistenceStore: StudioPersistenceStore(fileURL: storeURL))
        }
        await MainActor.run {
            appState.workspace = oldWs
            appState.selectedFilePaths = ["a.txt"]
            appState.mode = .workspace
        }

        await MainActor.run {
            appState.loadWorkspace(newWorkspace)
        }

        let selectedPaths = await MainActor.run { appState.selectedFilePaths }
        XCTAssertTrue(selectedPaths.isEmpty, "Switching workspaces should clear checked files")
    }

    // MARK: - Cancel in-flight on mode switch

    func testCancelChatForSwitchClearsActiveState() async throws {
        let storeURL = self.storeURL!
        let appState = await MainActor.run {
            AppState(persistenceStore: StudioPersistenceStore(fileURL: storeURL))
        }
        await MainActor.run {
            appState.isChatting = true
            appState.mode = .generalChat
            appState.showDashboard()
        }

        let isChatting = await MainActor.run { appState.isChatting }
        XCTAssertFalse(isChatting, "Switching modes should cancel in-flight chat")
    }

    func testCancelExecutionForSwitchClearsActiveState() async throws {
        let storeURL = self.storeURL!
        let appState = await MainActor.run {
            AppState(persistenceStore: StudioPersistenceStore(fileURL: storeURL))
        }
        await MainActor.run {
            appState.isExecutingTask = true
            appState.showDashboard()
        }

        let isExecuting = await MainActor.run { appState.isExecutingTask }
        XCTAssertFalse(isExecuting, "Switching modes should cancel in-flight execution")
    }

    // MARK: - Mode switching preserves persistence

    func testShowDashboardPersistsState() async throws {
        let tempDir = self.tempDir!
        let storeURL = self.storeURL!
        let workspace = makeWorkspace(in: tempDir)
        let appState = await MainActor.run {
            AppState(persistenceStore: StudioPersistenceStore(fileURL: storeURL))
        }
        await MainActor.run {
            appState.recentWorkspaces = [RecentWorkspace(name: workspace.name, path: workspace.path, kind: workspace.kind, openedAt: Date(), totalFiles: workspace.summary.totalFiles)]
            appState.workspace = workspace
            appState.selectedFilePaths = ["a.txt"]
            appState.showDashboard()
        }

        let persisted = StudioPersistenceStore(fileURL: storeURL).load()
        XCTAssertFalse(persisted.recentWorkspaces.isEmpty, "Recent workspaces should remain persisted when leaving a workspace")
    }

    // MARK: - removeRecentWorkspace clears active state

    func testRemoveRecentWorkspaceClearsWhenActive() async throws {
        let tempDir = self.tempDir!
        let storeURL = self.storeURL!
        let workspace = makeWorkspace(in: tempDir)
        let appState = await MainActor.run {
            AppState(persistenceStore: StudioPersistenceStore(fileURL: storeURL))
        }
        await MainActor.run {
            appState.workspace = workspace
            appState.mode = .workspace
            let recent = RecentWorkspace(name: "Test", path: tempDir.path, kind: .general, openedAt: Date(), totalFiles: 0)
            appState.recentWorkspaces.append(recent)
            appState.removeRecentWorkspace(recent)
        }

        let mode = await MainActor.run { appState.mode }
        let workspaceRef = await MainActor.run { appState.workspace }
        XCTAssertEqual(mode, .dashboard)
        XCTAssertNil(workspaceRef)
    }

    // MARK: - Context key isolation

    func testContextKeyDiffersByMode() async throws {
        let tempDir = self.tempDir!
        let storeURL = self.storeURL!
        let workspace = makeWorkspace(in: tempDir)
        let appState = await MainActor.run {
            AppState(persistenceStore: StudioPersistenceStore(fileURL: storeURL))
        }

        let dashboardKey = await MainActor.run { appState.contextKey }
        XCTAssertEqual(dashboardKey, "dashboard")

        await MainActor.run {
            appState.startGeneralChat()
        }
        let generalKey = await MainActor.run { appState.contextKey }
        XCTAssertEqual(generalKey, "general")

        await MainActor.run {
            appState.workspace = workspace
            appState.mode = .workspace
        }
        let workspaceKey = await MainActor.run { appState.contextKey }
        XCTAssertEqual(workspaceKey, "workspace:\(tempDir.path)")
    }

    // MARK: - Workspace permissions loaded per path

    func testLoadWorkspaceLoadsPermissionsOverride() async throws {
        let tempDir = self.tempDir!
        let storeURL = self.storeURL!
        let appState = await MainActor.run {
            AppState(persistenceStore: StudioPersistenceStore(fileURL: storeURL))
        }
        let safePermissions = WorkspacePermissions.safeAutomation
        await MainActor.run {
            appState.workspacePermissionOverrides[tempDir.path] = safePermissions
            appState.loadWorkspace(tempDir)
        }

        let permissions = await MainActor.run { appState.permissions }
        XCTAssertEqual(permissions, safePermissions)
    }

    func testLoadWorkspaceDefaultsToAskEveryTime() async throws {
        let tempDir = self.tempDir!
        let storeURL = self.storeURL!
        let appState = await MainActor.run {
            AppState(persistenceStore: StudioPersistenceStore(fileURL: storeURL))
        }
        await MainActor.run {
            appState.loadWorkspace(tempDir)
        }

        let permissions = await MainActor.run { appState.permissions }
        XCTAssertEqual(permissions, .askEveryTime)
    }

    func testCanRunActiveTaskRequiresWorkspaceContextAndCheckedFiles() async throws {
        let tempDir = self.tempDir!
        let storeURL = self.storeURL!
        let appState = await MainActor.run {
            AppState(persistenceStore: StudioPersistenceStore(fileURL: storeURL))
        }
        try createFiles(at: ["a.txt"], in: tempDir)
        let workspace = makeWorkspace(in: tempDir)

        await MainActor.run {
            appState.workspace = workspace
            appState.mode = .workspace
            appState.activeTemplate = appState.taskTemplates[0]
            appState.selectedFilePaths = []
        }

        let blocked = await MainActor.run { appState.canRunActiveTask }
        XCTAssertFalse(blocked)

        await MainActor.run {
            appState.selectedFilePaths = ["a.txt"]
        }

        let enabled = await MainActor.run { appState.canRunActiveTask }
        XCTAssertTrue(enabled)
    }

    func testRejectPlanMarksPlanRejectedWithoutMutatingFiles() async throws {
        let storeURL = self.storeURL!
        let appState = await MainActor.run {
            AppState(persistenceStore: StudioPersistenceStore(fileURL: storeURL))
        }

        let plan = FileOperationPlan(summary: "Test", operations: [
            RenamePlanRecord(currentPath: "a.txt", proposedPath: "archive", reason: "Archive it.", riskLevel: .low)
        ], requiresApproval: true)

        let thread = ChatThread(contextKey: "workspace:/tmp/test", title: "Plan Thread")
        var message = ChatMessage(role: .assistant, markdown: "Plan ready")
        message.filePlan = plan

        await MainActor.run {
            appState.chatThreads = [thread]
            appState.activeChatID = thread.id
            appState.chatThreads[0].messages = [message]
            appState.rejectPlan(messageID: message.id)
        }

        let approved = await MainActor.run {
            appState.chatThreads[0].messages[0].planApproved
        }
        XCTAssertEqual(approved, false)
    }

    func testApprovePlanRequiresWritePermissionAndAppliesDestinationMap() async throws {
        let tempDir = self.tempDir!
        let storeURL = self.storeURL!
        let source = tempDir.appendingPathComponent("source.txt")
        try "hello".write(to: source, atomically: true, encoding: .utf8)
        let workspace = Workspace(url: tempDir, kind: .code, files: [WorkspaceFile(url: source, relativePath: "source.txt", kind: .text, byteCount: 5)], summary: WorkspaceSummary(totalFiles: 1, totalBytes: 5), scannedAt: Date())

        let appState = await MainActor.run {
            AppState(persistenceStore: StudioPersistenceStore(fileURL: storeURL))
        }

        let plan = FileOperationPlan(summary: "Move source", operations: [
            RenamePlanRecord(currentPath: "source.txt", proposedPath: "archive", reason: "Archive it.", riskLevel: .low)
        ], requiresApproval: true)

        var message = ChatMessage(role: .assistant, markdown: "Plan ready")
        message.filePlan = plan
        let thread = ChatThread(contextKey: "workspace:\(tempDir.path)", title: "Plan Thread")

        await MainActor.run {
            appState.workspace = workspace
            appState.mode = .workspace
            appState.permissions = .safeAutomation
            appState.activeChatID = thread.id
            appState.chatThreads = [thread]
            appState.chatThreads[0].messages = [message]
            appState.selectedFilePaths = ["source.txt"]
            appState.approvePlan(messageID: message.id, destinations: ["source.txt": "archive"])
        }

        let isApproved = await MainActor.run { appState.chatThreads[0].messages[0].planApproved }
        XCTAssertEqual(isApproved, true)

        let destinationExists = FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("archive/source.txt").path)
        XCTAssertTrue(destinationExists)
    }
}
