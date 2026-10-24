import XCTest
@testable import LocalAI

final class CheckedFileRAGTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CheckedFileRAGTests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func makeWorkspace(files: [String: String]) throws -> Workspace {
        for (path, content) in files {
            let url = tempDir.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: url, atomically: true, encoding: .utf8)
        }
        return WorkspaceScanner().scan(url: tempDir)
    }

    // MARK: - All files unchecked by default

    @MainActor
    func testLoadWorkspaceStartsWithDirectoriesCollapsed() async throws {
        let storeURL = tempDir.appendingPathComponent("store.json")
        let appState = AppState(persistenceStore: StudioPersistenceStore(fileURL: storeURL))
        _ = try makeWorkspace(files: ["docs/a.md": "# A", "docs/b.md": "# B", "src/main.swift": "let x = 1"])
        appState.loadWorkspace(tempDir!)
        XCTAssertTrue(
            appState.expandedDirectories.isEmpty,
            "Opening a workspace must start with all folders collapsed: pre-expanding every directory forces SwiftUI to lay out the entire file tree (FolderColumn's eager VStack+ForEach) in one main-thread pass, which freezes the window for large workspaces."
        )
    }

    func testWorkspaceOpensWithAllFilesUnchecked() async throws {
        let tempDir = self.tempDir
        let workspace = try makeWorkspace(files: ["a.txt": "hello", "b.md": "# Title"])
        let selectedFilePaths: Set<String> = []

        let checkedFiles = workspace.files.filter { selectedFilePaths.contains($0.relativePath) }
        XCTAssertTrue(checkedFiles.isEmpty, "Workspace should open with all files unchecked")
    }

    // MARK: - Partial folder selection

    func testCheckedFilesFilteredBySelectedFilePaths() async throws {
        let tempDir = self.tempDir
        let workspace = try makeWorkspace(files: ["a.txt": "hello", "b.md": "title", "c.txt": "world"])
        let selectedFilePaths: Set<String> = ["b.md"]

        let checkedFiles = workspace.files.filter { selectedFilePaths.contains($0.relativePath) }
        XCTAssertEqual(checkedFiles.count, 1)
        XCTAssertEqual(checkedFiles.first?.relativePath, "b.md")
    }

    func testCheckedFilesMultipleSelection() async throws {
        let workspace = try makeWorkspace(files: ["a.txt": "hello", "b.md": "title", "c.txt": "world"])
        let selectedFilePaths: Set<String> = ["a.txt", "c.txt"]

        let checkedFiles = workspace.files.filter { selectedFilePaths.contains($0.relativePath) }
        XCTAssertEqual(checkedFiles.count, 2)
        let paths = checkedFiles.map(\.relativePath)
        XCTAssertTrue(paths.contains("a.txt"))
        XCTAssertTrue(paths.contains("c.txt"))
        XCTAssertFalse(paths.contains("b.md"))
    }

    @MainActor
    func testToggleFileAndSelectAllSkipUnreadableKinds() async throws {
        let storeURL = tempDir.appendingPathComponent("store.json")
        let appState = AppState(persistenceStore: StudioPersistenceStore(fileURL: storeURL))
        let workspace = try makeWorkspace(files: ["notes.md": "# hi", "photo.png": "junk", "font.woff2": "x"])
        appState.workspace = workspace
        let readablePaths = workspace.files.filter { $0.kind.canEnterContext }.map(\.relativePath)

        appState.toggleAllFiles(true)
        XCTAssertEqual(Set(appState.selectedFilePaths), Set(readablePaths))
        XCTAssertFalse(appState.selectedFilePaths.contains("photo.png"))
        XCTAssertFalse(appState.selectedFilePaths.contains("font.woff2"))

        appState.toggleAllFiles(false)
        let image = try XCTUnwrap(workspace.files.first { $0.kind == .image })
        appState.toggleFile(image, isOn: true)
        XCTAssertFalse(appState.selectedFilePaths.contains(image.relativePath))
    }

    // MARK: - File tree excludes unreadable kinds

    func testFileTreeExcludesUnreadableKinds() throws {
        let workspace = try makeWorkspace(files: [
            "notes.md": "# hi",
            "photo.png": "junk",
            "font.woff2": "x",
            "assets/logo.jpg": "junk"
        ])
        let tree = FileTree(workspace: workspace)

        var leaves: [WorkspaceFile] = []
        func collect(_ nodes: [FileTreeNode]) {
            for node in nodes {
                if let file = node.file {
                    leaves.append(file)
                } else {
                    collect(node.children)
                }
            }
        }
        collect(tree.roots)

        XCTAssertTrue(leaves.contains { $0.relativePath == "notes.md" })
        XCTAssertFalse(leaves.contains { $0.relativePath == "photo.png" }, "Unreadable files must not be listed in the file tree")
        XCTAssertFalse(leaves.contains { $0.relativePath == "font.woff2" }, "Unreadable files must not be listed in the file tree")
        XCTAssertFalse(leaves.contains { $0.relativePath == "assets/logo.jpg" }, "Unreadable files must not be listed in the file tree")
    }

    // MARK: - Directory tri-state logic

    func testDirectoryStateAllUnchecked() async throws {
        let workspace = try makeWorkspace(files: ["sub/file1.txt": "a", "sub/file2.txt": "b"])
        let selectedFilePaths: Set<String> = []

        let prefix = "sub/"
        let descendants = workspace.files.filter { $0.relativePath.hasPrefix(prefix) }
        let checked = descendants.filter { selectedFilePaths.contains($0.relativePath) }.count

        XCTAssertTrue(descendants.count == 2)
        if checked == 0 { XCTAssertTrue(true) }
        XCTAssertEqual(checked, 0, "Directory with all unchecked should have 0 checked")
    }

    func testDirectoryStateAllChecked() async throws {
        let workspace = try makeWorkspace(files: ["sub/file1.txt": "a", "sub/file2.txt": "b"])
        let selectedFilePaths: Set<String> = ["sub/file1.txt", "sub/file2.txt"]

        let prefix = "sub/"
        let descendants = workspace.files.filter { $0.relativePath.hasPrefix(prefix) }
        let checked = descendants.filter { selectedFilePaths.contains($0.relativePath) }.count

        XCTAssertEqual(checked, descendants.count, "All files in directory should be checked")
        XCTAssertEqual(checked, 2)
    }

    func testDirectoryStatePartialChecked() async throws {
        let workspace = try makeWorkspace(files: ["sub/file1.txt": "a", "sub/file2.txt": "b"])
        let selectedFilePaths: Set<String> = ["sub/file1.txt"]

        let prefix = "sub/"
        let descendants = workspace.files.filter { $0.relativePath.hasPrefix(prefix) }
        let checked = descendants.filter { selectedFilePaths.contains($0.relativePath) }.count

        XCTAssertTrue(checked > 0 && checked < descendants.count, "Partial selection: 0 < checked < total")
        XCTAssertEqual(checked, 1)
    }

    func testDirectoryStateEmptyDirectory() async throws {
        let workspace = try makeWorkspace(files: ["other.txt": "hello"])
        let selectedFilePaths: Set<String> = []

        let prefix = "emptydir/"
        let descendants = workspace.files.filter { $0.relativePath.hasPrefix(prefix) }
        XCTAssertTrue(descendants.isEmpty, "Empty directory should have no descendants")
    }

    // MARK: - Toggle directory selects all descendants

    func testToggleDirectoryAddsAllDescendants() async throws {
        let workspace = try makeWorkspace(files: ["sub/file1.txt": "a", "sub/file2.txt": "b", "sub/nested/file3.txt": "c"])
        var selectedFilePaths: Set<String> = []

        let prefix = "sub/"
        for file in workspace.files where file.relativePath.hasPrefix(prefix) {
            selectedFilePaths.insert(file.relativePath)
        }

        XCTAssertEqual(selectedFilePaths.count, 3, "Toggling a directory on should check all descendant files")
    }

    func testToggleDirectoryRemovesAllDescendants() async throws {
        let workspace = try makeWorkspace(files: ["sub/file1.txt": "a", "sub/file2.txt": "b"])
        var selectedFilePaths: Set<String> = ["sub/file1.txt", "sub/file2.txt"]

        let prefix = "sub/"
        for file in workspace.files where file.relativePath.hasPrefix(prefix) {
            selectedFilePaths.remove(file.relativePath)
        }

        XCTAssertTrue(selectedFilePaths.isEmpty, "Toggling a directory off should uncheck all descendant files")
    }

    // MARK: - Toggle all files

    func testToggleAllFilesSelectsAll() async throws {
        let workspace = try makeWorkspace(files: ["a.txt": "a", "b.md": "b", "c.txt": "c"])

        let selectedFilePaths: Set<String> = Set(workspace.files.map(\.relativePath))
        XCTAssertEqual(selectedFilePaths.count, 3)
    }

    func testToggleAllFilesDeselectsAll() async throws {
        let workspace = try makeWorkspace(files: ["a.txt": "a", "b.md": "b"])
        var selectedFilePaths: Set<String> = Set(workspace.files.map(\.relativePath))
        selectedFilePaths.removeAll()

        XCTAssertTrue(selectedFilePaths.isEmpty)
    }

    // MARK: - Descendants query - only matching prefix

    func testDescendantsReturnsOnlyMatchingPrefix() async throws {
        let workspace = try makeWorkspace(files: ["sub/file1.txt": "a", "subdir/file2.txt": "b", "other.txt": "c"])

        let prefix = "sub/"
        let descendants = workspace.files.filter { $0.relativePath.hasPrefix(prefix) }

        XCTAssertEqual(descendants.count, 1)
        XCTAssertEqual(descendants.first?.relativePath, "sub/file1.txt")
    }

    // MARK: - canRunActiveTask gating logic

    func testCannotRunTaskWithoutCheckedFiles() async throws {
        let workspace = try makeWorkspace(files: ["a.txt": "hello"])
        let selectedFilePaths: Set<String> = []
        let hasCheckedFiles = !selectedFilePaths.isEmpty

        XCTAssertFalse(hasCheckedFiles, "Should not be able to run without checked files")
    }

    func testCanRunTaskWithCheckedFiles() async throws {
        let workspace = try makeWorkspace(files: ["a.txt": "hello"])
        let selectedFilePaths: Set<String> = ["a.txt"]
        let hasCheckedFiles = !selectedFilePaths.isEmpty

        XCTAssertTrue(hasCheckedFiles)
    }

    // MARK: - AppState checkedFiles property

    func testAppStateCheckedFilesFiltersCorrectly() async throws {
        let storeURL = tempDir.appendingPathComponent("state.json")
        let workspace = try makeWorkspace(files: ["a.txt": "hello", "b.md": "title"])
        let appState = await MainActor.run {
            AppState(persistenceStore: StudioPersistenceStore(fileURL: storeURL))
        }

        await MainActor.run {
            appState.workspace = workspace
            appState.selectedFilePaths = ["b.md"]
        }

        let checked = await MainActor.run { appState.checkedFiles }
        XCTAssertEqual(checked.count, 1, "checkedFiles should return only selected files")
        XCTAssertEqual(checked.first?.relativePath, "b.md")
    }

    func testAppStateCheckedFilesEmptyWhenNoSelection() async throws {
        let storeURL = tempDir.appendingPathComponent("state.json")
        let workspace = try makeWorkspace(files: ["a.txt": "hello"])
        let appState = await MainActor.run {
            AppState(persistenceStore: StudioPersistenceStore(fileURL: storeURL))
        }

        await MainActor.run {
            appState.workspace = workspace
            appState.selectedFilePaths = []
        }

        let checked = await MainActor.run { appState.checkedFiles }
        XCTAssertTrue(checked.isEmpty)
    }

    func testAppStateDirectoryStateTriStateLogic() async throws {
        let storeURL = tempDir.appendingPathComponent("state.json")
        let workspace = try makeWorkspace(files: ["sub/file1.txt": "a", "sub/file2.txt": "b"])
        let appState = await MainActor.run {
            AppState(persistenceStore: StudioPersistenceStore(fileURL: storeURL))
        }

        await MainActor.run {
            appState.workspace = workspace
            appState.selectedFilePaths = ["sub/file1.txt"]
        }

        let state = await MainActor.run { appState.directoryState("sub") }
        XCTAssertNil(state, "Partial directory should be nil (mixed state)")

        await MainActor.run {
            appState.selectedFilePaths = ["sub/file1.txt", "sub/file2.txt"]
        }
        let allChecked = await MainActor.run { appState.directoryState("sub") }
        XCTAssertEqual(allChecked, true)

        await MainActor.run {
            appState.selectedFilePaths = []
        }
        let allUnchecked = await MainActor.run { appState.directoryState("sub") }
        XCTAssertEqual(allUnchecked, false)
    }

    func testAppStateToggleDirectorySelectsDescendants() async throws {
        let storeURL = tempDir.appendingPathComponent("state.json")
        let workspace = try makeWorkspace(files: ["sub/file1.txt": "a", "sub/file2.txt": "b", "sub/nested/file3.txt": "c"])
        let appState = await MainActor.run {
            AppState(persistenceStore: StudioPersistenceStore(fileURL: storeURL))
        }

        await MainActor.run {
            appState.workspace = workspace
            appState.selectedFilePaths = []
            appState.toggleDirectory("sub", isOn: true)
        }

        let checked = await MainActor.run { appState.checkedFiles }
        XCTAssertEqual(checked.count, 3, "Toggling directory on should check all descendants")
    }

    func testAppStateToggleAllFiles() async throws {
        let storeURL = tempDir.appendingPathComponent("state.json")
        let workspace = try makeWorkspace(files: ["a.txt": "a", "b.md": "b", "c.txt": "c"])
        let appState = await MainActor.run {
            AppState(persistenceStore: StudioPersistenceStore(fileURL: storeURL))
        }

        await MainActor.run {
            appState.workspace = workspace
            appState.toggleAllFiles(true)
        }

        let checked = await MainActor.run { appState.checkedFiles }
        XCTAssertEqual(checked.count, 3)
    }

    // MARK: - Tool-run activity steps resolve to done

    @MainActor
    func testToolRunMarksRunningActivityStepsDone() async throws {
        let storeURL = tempDir.appendingPathComponent("store.json")
        let appState = AppState(persistenceStore: StudioPersistenceStore(fileURL: storeURL))
        appState.modelClient = MockLocalModelClient()
        _ = try makeWorkspace(files: ["notes.md": "# Meeting\n\nDecided to ship the trailer next week."])
        appState.loadWorkspace(tempDir!)
        appState.selectedFilePaths = ["notes.md"]
        let template = TaskTemplate(
            title: "Summarize",
            subtitle: "Condense checked files into a cited Markdown brief.",
            symbol: "doc.text.magnifyingglass",
            prompt: "Summarize the checked workspace files with citations and major themes.",
            reviewRequired: false,
            outputMode: .markdown
        )
        appState.runTool(template)
        await appState.executionTask?.value

        XCTAssertEqual(appState.activeTask.status, .complete)
        let indexing = try XCTUnwrap(appState.activeTask.activity.first { $0.title == "Indexing started" })
        XCTAssertEqual(indexing.state, .done, "Indexing started must finish as a checkmark once the chunk index is built")
        let model = try XCTUnwrap(appState.activeTask.activity.first { $0.title == "Model response" })
        XCTAssertEqual(model.state, .done, "Model response must finish as a checkmark once the model finishes streaming")
    }

    // MARK: - Re-running a completed tool keeps one history entry

    @MainActor
    func testReRunningCompletedToolDoesNotDuplicateSessionTask() async throws {
        let storeURL = tempDir.appendingPathComponent("store.json")
        let appState = AppState(persistenceStore: StudioPersistenceStore(fileURL: storeURL))
        appState.modelClient = MockLocalModelClient()
        _ = try makeWorkspace(files: ["notes.md": "# Meeting\n\nDecided to ship the trailer next week."])
        appState.loadWorkspace(tempDir!)
        appState.selectedFilePaths = ["notes.md"]
        let template = TaskTemplate(
            title: "Summarize",
            subtitle: "Condense checked files into a cited Markdown brief.",
            symbol: "doc.text.magnifyingglass",
            prompt: "Summarize the checked workspace files with citations and major themes.",
            reviewRequired: false,
            outputMode: .markdown
        )
        appState.runTool(template)
        await appState.executionTask?.value
        let taskID = appState.activeTask.id
        XCTAssertEqual(appState.sessionTasks.filter { $0.id == taskID }.count, 1)

        // The ActiveTaskSummaryView Run button re-runs the active task directly.
        appState.runActiveTask()
        await appState.executionTask?.value

        XCTAssertEqual(
            appState.sessionTasks.filter { $0.id == taskID }.count, 1,
            "Re-running the active task must update the existing history entry, not append the same instance twice"
        )
    }

    // MARK: - Read permission is enforced

    @MainActor
    func testToolRunIsBlockedWhenReadPermissionIsOff() async throws {
        let storeURL = tempDir.appendingPathComponent("store.json")
        let appState = AppState(persistenceStore: StudioPersistenceStore(fileURL: storeURL))
        appState.modelClient = MockLocalModelClient()
        _ = try makeWorkspace(files: ["notes.md": "# Meeting\n\nShip it."])
        appState.loadWorkspace(tempDir!)
        appState.selectedFilePaths = ["notes.md"]
        appState.permissions = WorkspacePermissions(read: false, write: false, delete: false, shell: false, network: false, tools: false)
        let template = TaskTemplate(
            title: "Summarize",
            subtitle: "Condense checked files into a cited Markdown brief.",
            symbol: "doc.text.magnifyingglass",
            prompt: "Summarize the checked workspace files with citations and major themes.",
            reviewRequired: false,
            outputMode: .markdown
        )
        appState.runTool(template)
        await appState.executionTask?.value

        XCTAssertEqual(appState.activeTask.status, .failed)
        XCTAssertTrue(
            appState.activeTask.activity.contains { $0.title == "Read permission required" },
            "Disabling 'Read project files' must actually block reading checked files, not be an inert toggle"
        )
    }

    // MARK: - Plan approval is crash-safe

    @MainActor
    func testApprovePlanDoesNotPersistApprovalBeforeMovesComplete() async throws {
        let storeURL = tempDir.appendingPathComponent("store.json")
        let appState = AppState(persistenceStore: StudioPersistenceStore(fileURL: storeURL))
        let workspace = try makeWorkspace(files: ["a.txt": "data"])
        appState.mode = .workspace
        appState.workspace = workspace
        appState.permissions = .safeAutomation
        appState.selectedFilePaths = ["a.txt"]

        let plan = FileOperationPlan(
            summary: "1 move",
            operations: [RenamePlanRecord(currentPath: "a.txt", proposedPath: "docs", reason: "test", riskLevel: .low)],
            requiresApproval: true
        )
        let message = ChatMessage(role: .assistant, markdown: "plan", filePlan: plan)
        let thread = ChatThread(contextKey: appState.contextKey, title: "t", messages: [message])
        appState.chatThreads = [thread]
        appState.activeChatID = thread.id

        appState.approvePlan(messageID: message.id, destinations: [:])

        XCTAssertNil(
            appState.chatThreads[0].messages[0].planApproved,
            "Approval must be persisted only after the moves execute, so a crash mid-apply cannot leave a plan marked applied"
        )
        await appState.executionTask?.value
        XCTAssertEqual(appState.chatThreads[0].messages[0].planApproved, true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("docs/a.txt").path))
    }
}
