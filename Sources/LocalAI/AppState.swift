import AppKit
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var mode: StudioMode = .dashboard
    @Published var workspace: Workspace?
    @Published var selectedFile: WorkspaceFile?
    @Published var selectedFilePaths: Set<String> = []
    @Published var expandedDirectories: Set<String> = []
    @Published var recentWorkspaces: [RecentWorkspace] = []
    @Published var chatThreads: [ChatThread] = []
    @Published var activeChatID: UUID?
    @Published var savedResponses: [SavedResponse] = []
    @Published var activeTask: StudioTask
    @Published var sessionTasks: [StudioTask] = []
    @Published var isChatting = false
    @Published var activeTemplate: TaskTemplate?
    @Published var permissionMode: PermissionMode = .askEveryTime
    @Published var permissions = WorkspacePermissions.askEveryTime
    @Published var isScanning = false
    @Published var isExecutingTask = false
    @Published var indexSummary: ChunkIndexSummary?
    @Published var indexStatusMessage: String?
    @Published var contextBudget = AppState.makeContextBudget(limit: 4096)
    @Published var modelStatus = ModelStatus(
        title: "Local Model",
        detail: "Checking model availability.",
        isAvailable: false,
        contextWindow: 4096
    )
    @Published var mcpServers: [MCPServerConfig] = []
    @Published var workspaceMCPSettings: [String: WorkspaceMCPSettings] = [:]
    @Published var workspaceNameOverrides: [String: String] = [:]
    @Published var workspacePermissionOverrides: [String: WorkspacePermissions] = [:]
    let mcpTransportReady = false

    let scanner = WorkspaceScanner()
    var modelClient: any LocalModelClient = LocalModelClientFactory.make()
    private let persistenceStore: StudioPersistenceStore
    var executionTask: Task<Void, Never>?
    private var chatTask: Task<Void, Never>?
    private var tasksByContext: [String: [StudioTask]] = [:]
    private var planApprovalsInFlight: Set<UUID> = []

    var contextKey: String {
        switch mode {
        case .dashboard: "dashboard"
        case .generalChat: "general"
        case .workspace: workspace.map { "workspace:\($0.path)" } ?? "workspace"
        }
    }

    var activeChat: ChatThread? {
        guard let activeChatID else { return nil }
        return chatThreads.first { $0.id == activeChatID }
    }

    var currentMessages: [ChatMessage] {
        activeChat?.messages ?? []
    }

    var currentSavedResponses: [SavedResponse] {
        savedResponses
            .filter { $0.contextKey == contextKey }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var contextChatThreads: [ChatThread] {
        chatThreads
            .filter { $0.contextKey == contextKey }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private var checkedFilesCache: (key: String, files: [WorkspaceFile])?

    var checkedFiles: [WorkspaceFile] {
        guard let workspace else { return [] }
        let key = "\(workspace.url.path)|\(workspace.scannedAt.timeIntervalSince1970)|\(selectedFilePaths.hashValue)"
        if let cache = checkedFilesCache, cache.key == key { return cache.files }
        let files = workspace.files.filter { selectedFilePaths.contains($0.relativePath) }
        checkedFilesCache = (key, files)
        return files
    }

    var currentWorkspaceMCPSettings: WorkspaceMCPSettings {
        guard let workspace else { return WorkspaceMCPSettings() }
        return workspaceMCPSettings[workspace.path, default: WorkspaceMCPSettings()]
    }

    var workspaceDisplayName: String {
        guard let workspace else { return "Workspace" }
        return workspaceNameOverrides[workspace.path] ?? workspace.name
    }

    func saveWorkspaceDisplayName(_ name: String, path: String? = nil) {
        let targetPath = path ?? workspace?.path
        guard let targetPath else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            workspaceNameOverrides.removeValue(forKey: targetPath)
        } else {
            workspaceNameOverrides[targetPath] = trimmed
        }
        if let idx = recentWorkspaces.firstIndex(where: { $0.path == targetPath }), !trimmed.isEmpty {
            recentWorkspaces[idx].name = trimmed
        }
        persist()
    }

    func workspaceDisplayName(for path: String, fallback: String) -> String {
        workspaceNameOverrides[path] ?? fallback
    }

    func mcpSettings(for path: String) -> WorkspaceMCPSettings {
        workspaceMCPSettings[path, default: WorkspaceMCPSettings()]
    }

    func permissions(for path: String?) -> WorkspacePermissions {
        guard let path else { return permissions }
        if path == workspace?.path { return permissions }
        return workspacePermissionOverrides[path, default: .askEveryTime]
    }

    func savePermissions(_ newPermissions: WorkspacePermissions, for path: String?) {
        guard let targetPath = path ?? workspace?.path else { return }
        workspacePermissionOverrides[targetPath] = newPermissions
        if workspace?.path == targetPath {
            permissions = newPermissions
            permissionMode = PermissionMode.derived(from: newPermissions)
            refreshReviewGate()
        }
        persist()
    }

    var mcpStatus: MCPStatus {
        MCPStatus(
            localServers: mcpServers.filter { !$0.transport.isRemote }.count,
            remoteServers: mcpServers.filter { $0.transport.isRemote }.count,
            enabledTools: 0
        )
    }

    var canRunActiveTask: Bool {
        mode == .workspace
            && workspace != nil
            && activeTemplate != nil
            && !isExecutingTask
            && !(activeTask.fileOperationPlan != nil)
            && !selectedFilePaths.isEmpty
    }

    var canCancelActiveTask: Bool {
        isExecutingTask
    }

    var checkedContextTokens: Int {
        checkedFiles.reduce(0) { $0 + Self.estimatedTokens(for: $1) }
    }

    static let instructionsReserve = 120
    static let expectedResponseReserve = 512
    static let promptOverheadReserve = 320

    static func makeContextBudget(limit: Int) -> ContextBudget {
        let fixed = instructionsReserve + expectedResponseReserve + promptOverheadReserve
        return ContextBudget(
            limit: limit,
            instructions: instructionsReserve,
            selectedChunks: max(1, Int(Double(max(0, limit - fixed)) * 0.8)),
            expectedResponse: expectedResponseReserve,
            promptOverhead: promptOverheadReserve
        )
    }

    var liveContextBudget: ContextBudget {
        ContextBudget(
            limit: contextBudget.limit,
            instructions: contextBudget.instructions,
            selectedChunks: min(checkedContextTokens, contextBudget.contentBudget),
            expectedResponse: contextBudget.expectedResponse
        )
    }

    private static func estimatedTokens(for file: WorkspaceFile) -> Int {
        switch file.kind {
        case .image, .folder:
            return 0
        default:
            let charsPerToken = (file.kind == .code || file.kind == .data) ? 3.0 : 3.5
            return max(1, Int(Double(file.byteCount) / charsPerToken))
        }
    }

    private static func estimatedTokens(for text: String) -> Int {
        max(1, Int(ceil(Double(text.count) / 3.5)))
    }

    let taskTemplates: [TaskTemplate] = [
        TaskTemplate(title: "Summarize", subtitle: "Condense checked files into a cited Markdown brief.", symbol: "doc.text.magnifyingglass", prompt: "Summarize the checked workspace files with citations and major themes.", reviewRequired: false, outputMode: .markdown),
        TaskTemplate(title: "Extract Actions", subtitle: "Find TODOs, decisions, owners, dates, and source files.", symbol: "checklist", prompt: "Extract action items from the checked workspace files.", reviewRequired: false, outputMode: .actionItems),
        TaskTemplate(title: "Organize Files", subtitle: "Propose safe folders for checked files.", symbol: "folder.badge.gearshape", prompt: "Create a safe file organization plan for checked files only. Start your response with a fenced json block exactly in this shape, listing every checked file exactly once:\n\n```json\n{\"operations\":[{\"from\":\"README.md\",\"to\":\"docs\"}]}\n```\n\nThen add a short bulleted rationale. Rules: \"from\" must be a checked file path exactly as listed; \"to\" must be a relative folder path inside the workspace root; keep to a small number of folders; never omit a checked file from the json operations.", reviewRequired: true, outputMode: .filePlan, required: .write),
        TaskTemplate(title: "Explain Codebase", subtitle: "Detect architecture, entry points, tests, and scripts.", symbol: "curlybraces.square", prompt: "Explain this code workspace from the checked files in plain English.", reviewRequired: false, outputMode: .markdown),
        TaskTemplate(title: "Extract to JSON", subtitle: "Convert checked notes or documents into schema-valid records.", symbol: "curlybraces", prompt: "Extract structured JSON records from checked workspace content.", reviewRequired: false, outputMode: .structuredJSON)
    ]

    init(persistenceStore: StudioPersistenceStore = StudioPersistenceStore(secretStore: KeychainSecretStore())) {
        AppSupport.migrateLegacyContainer()
        self.persistenceStore = persistenceStore
        let snapshot = persistenceStore.load()
        recentWorkspaces = snapshot.recentWorkspaces
        chatThreads = snapshot.chatThreads
        savedResponses = snapshot.savedResponses
        tasksByContext = snapshot.tasksByContext
        mcpServers = snapshot.mcpServers
        workspaceMCPSettings = snapshot.workspaceMCPSettings
        workspaceNameOverrides = snapshot.workspaceNameOverrides
        workspacePermissionOverrides = snapshot.workspacePermissions
        sessionTasks = tasksByContext["general"] ?? []
        activeTask = StudioTask(
            title: "Ready",
            prompt: "Choose a chat or open a workspace.",
            outputMode: .markdown,
            status: .draft,
            plan: ["Start general chat or open a local folder.", "Choose checked files for workspace context.", "Run chat or a predefined tool.", "Save useful responses for the current context."],
            activity: [ActivityEvent(title: "Dashboard ready", detail: "Recent workspaces and general chat are available.", state: .done)]
        )

        Task {
            await refreshModelStatus()
        }
    }

    func refreshModelStatus() async {
        let status = await modelClient.availability()
        modelStatus = status
        contextBudget.limit = status.contextWindow
    }

    func showDashboard() {
        cancelChatForSwitch()
        mode = .dashboard
        workspace = nil
        selectedFile = nil
        selectedFilePaths = []
        expandedDirectories = []
        activeChatID = nil
        activeTemplate = nil
        indexSummary = nil
        indexStatusMessage = nil
        sessionTasks = []
        persist()
    }

    func startGeneralChat() {
        cancelChatForSwitch()
        mode = .generalChat
        workspace = nil
        selectedFile = nil
        selectedFilePaths = []
        expandedDirectories = []
        indexSummary = nil
        indexStatusMessage = nil
        activeTemplate = nil
        sessionTasks = tasksByContext["general"] ?? []
        activateOrCreateChat(contextKey: "general", title: "New chat")
    }

    func openWorkspace() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder for AFM Local AI to inspect."
        panel.prompt = "Open Workspace"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadWorkspace(url)
    }

    func openRecentWorkspace(_ recent: RecentWorkspace) {
        loadWorkspace(URL(fileURLWithPath: recent.path))
    }

    func removeRecentWorkspace(_ recent: RecentWorkspace) {
        recentWorkspaces.removeAll { $0.path == recent.path }
        ChunkIndexStore().deleteIndex(for: recent.path)
        if workspace?.path == recent.path {
            showDashboard()
        }
        persist()
    }

    func loadWorkspace(_ url: URL) {
        cancelChatForSwitch()
        isScanning = true
        let scanned = scanner.scan(url: url)
        workspace = scanned
        mode = .workspace
        permissions = workspacePermissionOverrides[scanned.path, default: .askEveryTime]
        permissionMode = PermissionMode.derived(from: permissions)
        selectedFile = nil
        selectedFilePaths = []
        expandedDirectories = []
        indexSummary = nil
        indexStatusMessage = nil
        activeTemplate = nil
        contextBudget = Self.makeContextBudget(limit: modelStatus.contextWindow)
        sessionTasks = tasksByContext[contextKey] ?? []
        activateOrCreateChat(contextKey: contextKey, title: "\(scanned.name) chat")
        remember(workspace: scanned)
        activeTask = StudioTask(
            title: "Workspace Scan",
            prompt: "Understand \(scanned.name).",
            outputMode: .markdown,
            status: .complete,
            plan: ["Scan local files.", "Check only the files that should enter context.", "Choose chat or a predefined tool.", "Save useful responses into this workspace."],
            activity: [
                ActivityEvent(title: "Scanned files", detail: "\(scanned.summary.totalFiles) files found, \(scanned.summary.ignoredItems) ignored, \(scanned.summary.readableSize) total.", state: .done),
                ActivityEvent(title: "Detected workspace", detail: "\(scanned.kind.rawValue) workspace at \(scanned.path).", state: .done)
            ]
        )
        isScanning = false
        persist()
    }

    func toggleFile(_ file: WorkspaceFile, isOn: Bool) {
        guard file.kind.canEnterContext else { return }
        if isOn {
            selectedFilePaths.insert(file.relativePath)
        } else {
            selectedFilePaths.remove(file.relativePath)
        }
    }

    func toggleAllFiles(_ isOn: Bool) {
        guard let workspace else { return }
        selectedFilePaths = isOn
            ? Set(workspace.files.filter { $0.kind.canEnterContext }.map(\.relativePath))
            : []
    }

    func toggleDirectoryExpanded(_ directory: String) {
        if expandedDirectories.contains(directory) {
            expandedDirectories.remove(directory)
        } else {
            expandedDirectories.insert(directory)
        }
    }

    func toggleDirectoryExpandedRecursively(_ directory: String) {
        guard let workspace else { return }
        var ids = Set<String>([directory])
        let prefix = directory + "/"
        for file in workspace.files where file.relativePath.hasPrefix(prefix) {
            if let slash = file.relativePath.lastIndex(of: "/") {
                var dir = String(file.relativePath[file.relativePath.startIndex..<slash])
                while !dir.isEmpty {
                    ids.insert(dir)
                    if let slash2 = dir.lastIndex(of: "/") {
                        dir = String(dir[dir.startIndex..<slash2])
                    } else {
                        break
                    }
                }
            }
        }
        if expandedDirectories.contains(directory) {
            expandedDirectories.subtract(ids)
        } else {
            expandedDirectories.formUnion(ids)
        }
    }

    func toggleDirectory(_ directory: String, isOn: Bool) {
        guard let workspace else { return }
        let prefix = directory + "/"
        for file in workspace.files where file.relativePath.hasPrefix(prefix) {
            toggleFile(file, isOn: isOn)
        }
    }

    func descendants(of directory: String) -> [WorkspaceFile] {
        guard let workspace else { return [] }
        let prefix = directory + "/"
        return workspace.files.filter { $0.relativePath.hasPrefix(prefix) }
    }

    func directoryState(_ directory: String) -> Bool? {
        let files = descendants(of: directory)
        guard !files.isEmpty else { return false }
        let checked = files.filter { selectedFilePaths.contains($0.relativePath) }.count
        if checked == 0 { return false }
        if checked == files.count { return true }
        return nil
    }

    func selectFile(_ file: WorkspaceFile) {
        selectedFile = selectedFile?.relativePath == file.relativePath ? nil : file
    }

    func addMCPServer(_ server: MCPServerConfig) {
        guard !server.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        mcpServers.append(server)
        persist()
    }

    func updateMCPServer(_ server: MCPServerConfig) {
        guard let index = mcpServers.firstIndex(where: { $0.id == server.id }) else { return }
        mcpServers[index] = server
        persist()
    }

    func deleteMCPServer(_ serverID: UUID) {
        mcpServers.removeAll { $0.id == serverID }
        for (path, var settings) in workspaceMCPSettings {
            settings.enabledServerIDs.removeAll { $0 == serverID }
            workspaceMCPSettings[path] = settings
        }
        persist()
    }

    func isMCPServerEnabledInWorkspace(_ serverID: UUID, path: String? = nil) -> Bool {
        let targetPath = path ?? workspace?.path
        guard let targetPath else { return false }
        return mcpSettings(for: targetPath).enabledServerIDs.contains(serverID)
    }

    func setMCPServerEnabledInWorkspace(_ enabled: Bool, serverID: UUID, path: String? = nil) {
        let targetPath = path ?? workspace?.path
        guard let targetPath else { return }
        var settings = workspaceMCPSettings[targetPath, default: WorkspaceMCPSettings()]
        if enabled {
            if !settings.enabledServerIDs.contains(serverID) {
                settings.enabledServerIDs.append(serverID)
            }
        } else {
            settings.enabledServerIDs.removeAll { $0 == serverID }
        }
        workspaceMCPSettings[targetPath] = settings
        persist()
    }

    func selectTemplate(_ template: TaskTemplate) {
        activeTemplate = template
        let missing = self.missingPermissions(for: template)
        activeTask = StudioTask(
            title: template.title,
            prompt: template.prompt,
            outputMode: template.outputMode,
            status: .planned,
            plan: planSteps(for: template),
            activity: [
                ActivityEvent(title: "Tool selected", detail: template.subtitle, state: .done),
                ActivityEvent(title: "Context scope", detail: "\(selectedFilePaths.count) checked files will be used.", state: .pending),
                ActivityEvent(title: missing.isEmpty ? "Ready to run" : "Permissions required", detail: permissionDetail(for: template), state: missing.isEmpty ? .pending : .review)
            ]
        )
    }

    private func missingPermissions(for template: TaskTemplate) -> [String] {
        guard template.reviewRequired || !template.required.isEmpty else { return [] }
        var labels: [String] = []
        if template.required.contains(.write), !permissions.write { labels.append("Write files") }
        if template.required.contains(.delete), !permissions.delete { labels.append("Delete files") }
        if template.required.contains(.shell), !permissions.shell { labels.append("Shell commands") }
        if template.required.contains(.network), !permissions.network { labels.append("Network") }
        return labels
    }

    private func permissionDetail(for template: TaskTemplate) -> String {
        let missing = missingPermissions(for: template)
        guard !missing.isEmpty else {
            if template.reviewRequired { return "Run to propose file operations. Approval is required before any execute." }
            return "This tool is read-only."
        }
        return "Needs \(missing.joined(separator: ", ")) to execute. You can still run to draft a plan."
    }

    private func refreshReviewGate() {
        guard let template = activeTemplate,
              activeTask.status == .needsReview || activeTask.status == .planned else { return }
        let missing = missingPermissions(for: template)
        activeTask.status = .planned
        if let index = activeTask.activity.firstIndex(where: { $0.title == "Permissions required" || $0.title == "Ready to run" }) {
            activeTask.activity[index].title = missing.isEmpty ? "Ready to run" : "Permissions required"
            activeTask.activity[index].detail = permissionDetail(for: template)
            activeTask.activity[index].state = missing.isEmpty ? .pending : .review
        }
    }

    func runTool(_ template: TaskTemplate) {
        selectTemplate(template)
        runActiveTask()
    }

    func runActiveTask() {
        guard let workspace, let activeTemplate else { return }
        guard permissions.read else {
            activeTask.status = .failed
            activeTask.activity.append(ActivityEvent(title: "Read permission required", detail: "Reading project files is turned off in Workspace Settings. Enable \"Read project files\" to run tools.", state: .review))
            return
        }
        guard !selectedFilePaths.isEmpty else {
            activeTask.status = .failed
            activeTask.activity.append(ActivityEvent(title: "No files checked", detail: "Check at least one file before running a workspace tool.", state: .failed))
            return
        }
        let missing = missingPermissions(for: activeTemplate)
        if activeTemplate.reviewRequired,
           activeTemplate.outputMode == .filePlan,
           !missing.isEmpty {
            // Plan-only tools are consent-neutral: they only draft proposals,
            // and approval (gated on the Write permission) decides execution.
            activeTask.activity.append(ActivityEvent(title: "Permissions required", detail: permissionDetail(for: activeTemplate), state: .review))
        } else if !missing.isEmpty {
            activeTask.status = .failed
            activeTask.activity.append(ActivityEvent(title: "Permissions required", detail: permissionDetail(for: activeTemplate), state: .failed))
            return
        }
        appendMessage(ChatMessage(role: .user, markdown: activeTemplate.title))
        executionTask = Task { await execute(template: activeTemplate, workspace: workspace, showResult: true) }
    }

    func cancelActiveTask() {
        executionTask?.cancel()
        executionTask = nil
        isExecutingTask = false
        activeTask.status = .cancelled
        activeTask.activity.append(ActivityEvent(title: "Cancelled", detail: "The active tool was stopped by the user.", state: .failed))
    }

    func viewSessionTask(_ task: StudioTask) {
        activeTask = task
        activeTemplate = nil
    }

    func clearSession() {
        guard mode != .dashboard else { return }
        if let index = chatThreads.firstIndex(where: { $0.id == activeChatID }) {
            chatThreads[index].messages = []
            chatThreads[index].updatedAt = Date()
        }
        sessionTasks = []
        tasksByContext[contextKey] = []
        persist()
    }

    func deleteActiveChat() {
        guard let activeChatID else { return }
        deleteChat(id: activeChatID)
    }

    func deleteChat(_ thread: ChatThread) {
        deleteChat(id: thread.id)
    }

    private func deleteChat(id: UUID) {
        let deletedContextKey = contextKey
        chatThreads.removeAll { $0.id == id }
        if activeChatID == id {
            activeChatID = chatThreads
                .filter { $0.contextKey == deletedContextKey }
                .max(by: { $0.updatedAt < $1.updatedAt })?
                .id
        }
        persist()
    }

    func createChatForCurrentContext() {
        guard mode != .dashboard else { return }
        let title = mode == .generalChat ? "New chat" : "\(workspace?.name ?? "Workspace") chat"
        let thread = ChatThread(contextKey: contextKey, title: title)
        chatThreads.append(thread)
        activeChatID = thread.id
        persist()
    }

    func activateChat(_ thread: ChatThread) {
        activeChatID = thread.id
    }

    func renameActiveChat(_ title: String) {
        guard let index = chatThreads.firstIndex(where: { $0.id == activeChatID }) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        chatThreads[index].title = trimmed.isEmpty ? "Untitled chat" : trimmed
        chatThreads[index].isTitleEdited = true
        chatThreads[index].updatedAt = Date()
        persist()
    }

    func sendChat(_ raw: String) {
        let message = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !isChatting else { return }
        guard mode != .dashboard else { return }
        if activeChatID == nil {
            activateOrCreateChat(contextKey: contextKey, title: "New chat")
        }
        appendMessage(ChatMessage(role: .user, markdown: message))
        let priorMessages = Array(currentMessages.dropLast())
        autoTitleCurrentChat(from: message)
        isChatting = true

        let currentMode = mode
        let activeWorkspace = workspace
        let budget = contextBudget
        let groundedPrompt = currentMode == .workspace
            ? groundedWorkspacePrompt(userPrompt: message, taskPrompt: message)
            : message
        let template = TaskTemplate(
            title: currentMode == .generalChat ? "General Chat" : "Workspace Chat",
            subtitle: currentMode == .generalChat ? "Regular chat without workspace retrieval." : "Answer from checked workspace files.",
            symbol: "bubble.left.and.bubble.right",
            prompt: groundedPrompt,
            reviewRequired: false,
            outputMode: .questionAnswer
        )

        chatTask = Task {
            do {
                let selectedChunks: [TextChunk]
                if currentMode == .workspace, let activeWorkspace {
                    guard permissions.read else {
                        appendMessage(ChatMessage(role: .assistant, markdown: "> [!WARNING]\n> Reading project files is turned off in Workspace Settings, so this chat can't use checked files. Enable \"Read project files\" to continue."))
                        isChatting = false
                        chatTask = nil
                        return
                    }
                    let indexed = try await indexAndSelectOffMain(template: template, workspace: activeWorkspace, budget: budget)
                    indexSummary = indexed.summary
                    selectedChunks = indexed.selectedChunks
                    if selectedChunks.isEmpty {
                        appendMessage(ChatMessage(role: .assistant, markdown: "> [!WARNING]\n> I could not retrieve readable context from the checked files. Check supported files in the left panel, then try again."))
                        isChatting = false
                        chatTask = nil
                        return
                    }
                } else {
                    selectedChunks = []
                }
                let request = LocalModelRequest(
                    taskTitle: template.title,
                    prompt: template.prompt,
                    chunks: selectedChunks,
                    contextBudget: budget,
                    outputMode: .questionAnswer,
                    history: await makeConversationHistory(from: priorMessages, budget: budget, usedByChunks: selectedChunks.reduce(0) { $0 + $1.tokenEstimate })
                )
                var partial = ""
                var finalResult: LocalModelResult?
                try await forEachModelEvent(client: modelClient, request: request) { event in
                    switch event {
                    case .partialMarkdown(let markdown): partial = markdown
                    case .completed(let result): finalResult = result
                    }
                }
                let result = finalResult ?? LocalModelResult(markdown: partial, citations: [], tokenEstimate: budget.used)
                let base = chatFriendlyMarkdown(polishMarkdown(ChatMarkdownFormatter.nonBlankResponse(result.markdown)))
                appendMessage(ChatMessage(role: .assistant, markdown: base + ChatMarkdownFormatter.truncatedTableCue(base), citations: result.citations))
            } catch is CancellationError {
            } catch LocalModelError.contextSizeExceeded {
                appendMessage(ChatMessage(role: .assistant, markdown: "> [!ERROR]\n> The conversation grew past the model's context window. Start a new chat, or the history will be summarized on the next attempt."))
            } catch {
                appendMessage(ChatMessage(role: .assistant, markdown: "> [!ERROR]\n> Chat failed: \(error.localizedDescription)"))
            }
            isChatting = false
            chatTask = nil
        }
    }

    private func forEachModelEvent(client: any LocalModelClient, request: LocalModelRequest, body: (LocalModelEvent) async throws -> Void) async throws {
        func open<C: LocalModelClient>(_ c: C) async throws {
            for try await event in c.streamResponse(to: request) {
                try Task.checkCancellation()
                try await body(event)
            }
        }
        try await open(client)
    }

    @discardableResult
    private func streamTaskResult(for request: LocalModelRequest) async throws -> LocalModelResult {
        var finalResult: LocalModelResult?
        try await forEachModelEvent(client: modelClient, request: request) { event in
            switch event {
            case .partialMarkdown(let markdown):
                activeTask.resultMarkdown = polishMarkdown(markdown)
            case .completed(let result):
                finalResult = result
            }
        }
        return finalResult ?? LocalModelResult(markdown: activeTask.resultMarkdown ?? "", citations: [], tokenEstimate: request.contextBudget.used)
    }

    func saveResponse(title: String, markdown: String, kind: SavedResponseKind, sourceMessageID: UUID? = nil) {
        let response = SavedResponse(contextKey: contextKey, title: title, markdown: markdown, kind: kind, sourceMessageID: sourceMessageID)
        savedResponses.append(response)
        persist()
    }

    func deleteSavedResponse(_ response: SavedResponse) {
        savedResponses.removeAll { $0.id == response.id }
        persist()
    }

    func renameSavedResponse(_ response: SavedResponse, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = savedResponses.firstIndex(where: { $0.id == response.id }),
              savedResponses[index].title != trimmed else { return }
        savedResponses[index].title = trimmed
        persist()
    }

    @discardableResult
    func saveChatMessage(_ message: ChatMessage) -> Bool {
        let alreadySaved = savedResponses.contains { response in
            response.contextKey == contextKey && response.kind == .chat &&
                response.sourceMessageID == message.id
        }
        guard !alreadySaved else { return false }
        saveResponse(title: message.role == .assistant ? (activeChat?.title ?? "Chat response") : "User note", markdown: message.markdown, kind: .chat, sourceMessageID: message.id)
        return true
    }

    private func execute(template: TaskTemplate, workspace: Workspace, showResult: Bool) async {
        isExecutingTask = true
        activeTask.status = .running
        activeTask.resultMarkdown = nil
        activeTask.citations = []
        activeTask.actionItems = []
        activeTask.fileOperationPlan = nil
        activeTask.activity.append(ActivityEvent(title: "Indexing started", detail: "Reading checked files only.", state: .running))

        do {
            let indexedContext = try await indexAndSelectOffMain(template: template, workspace: workspace, budget: contextBudget)
            let summary = indexedContext.summary
            indexSummary = summary
            markRunningStepDone("Indexing started")
            activeTask.activity.append(ActivityEvent(title: "Chunk index saved", detail: "\(summary.chunks.count) chunks from \(summary.indexedFiles) checked files. Skipped \(summary.skippedFiles).", state: .done))

            let selected = indexedContext.selectedChunks
            let selectedTokens = selected.reduce(0) { $0 + $1.tokenEstimate }
            let requestBudget = ContextBudget(limit: contextBudget.limit, instructions: contextBudget.instructions, selectedChunks: selectedTokens, expectedResponse: contextBudget.expectedResponse, promptOverhead: contextBudget.promptOverhead)
            activeTask.activity.append(ActivityEvent(title: "Context selected", detail: "\(selected.count) chunks selected, about \(selectedTokens) tokens.", state: .done))

            guard !selected.isEmpty else {
                activeTask.status = .failed
                let warning = "> [!WARNING]\n> No readable chunks were available from the checked files. The tool did not run because AFM Local AI only uses checked workspace context."
                activeTask.resultMarkdown = warning
                activeTask.activity.append(ActivityEvent(title: "No retrievable context", detail: "The checked files did not produce readable chunks.", state: .failed))
                if showResult {
                    appendMessage(ChatMessage(role: .assistant, markdown: warning))
                }
                persist()
                isExecutingTask = false
                executionTask = nil
                return
            }

            activeTask.activity.append(ActivityEvent(title: "Model response", detail: "Sending checked local context to \(modelClient.displayName).", state: .running))
            let request = LocalModelRequest(taskTitle: template.title, prompt: groundedWorkspacePrompt(userPrompt: template.title, taskPrompt: template.prompt), chunks: selected, contextBudget: requestBudget, outputMode: template.outputMode, workspaceRoot: workspace.url, checkedFilePaths: Array(selectedFilePaths))
            let result: LocalModelResult
            do {
                result = try await streamTaskResult(for: request)
            } catch LocalModelError.contextSizeExceeded {
                activeTask.activity.append(ActivityEvent(title: "Context overflow, retrying", detail: "Narrowing the excerpt selection and retrying once with less context.", state: .running))
                let narrowed = selected.truncated(to: requestBudget.retryBudget.selectedChunks)
                guard !narrowed.isEmpty else { throw LocalModelError.contextSizeExceeded }
                let narrowedTokens = narrowed.reduce(0) { $0 + $1.tokenEstimate }
                let retryBudget = ContextBudget(limit: requestBudget.limit, instructions: requestBudget.instructions, selectedChunks: narrowedTokens, expectedResponse: requestBudget.expectedResponse, promptOverhead: requestBudget.promptOverhead)
                let retryRequest = LocalModelRequest(taskTitle: template.title, prompt: groundedWorkspacePrompt(userPrompt: template.title, taskPrompt: template.prompt), chunks: narrowed, contextBudget: retryBudget, outputMode: template.outputMode, workspaceRoot: workspace.url, checkedFilePaths: Array(selectedFilePaths))
                result = try await streamTaskResult(for: retryRequest)
            }
            markRunningStepDone("Model response")
            markRunningStepDone("Context overflow, retrying")
            var cleanMarkdown = polishMarkdown(ChatMarkdownFormatter.nonBlankResponse(result.markdown))
            var parsedPlan = result.fileOperationPlan
            if template.outputMode == .filePlan {
                if parsedPlan == nil, let extracted = PlanOperationParser.extract(from: result.markdown) {
                    cleanMarkdown = polishMarkdown(extracted.cleanMarkdown)
                    let valid = extracted.operations.filter { PlanOperationParser.validate(operation: $0, checkedPaths: selectedFilePaths, directory: workspace.url) == nil }
                    let skipped = extracted.operations.count - valid.count
                    if !valid.isEmpty {
                        parsedPlan = FileOperationPlan(
                            summary: "\(valid.count) move(s) proposed. Nothing has been changed until you approve.",
                            operations: valid.map {
                                RenamePlanRecord(currentPath: $0.from, proposedPath: $0.to, reason: $0.reason ?? "Suggested move.", riskLevel: .low)
                            },
                            requiresApproval: true
                        )
                    }
                    if skipped > 0 {
                        cleanMarkdown += "\n\n> [!NOTE]\n> \(skipped) proposed move(s) were skipped because they failed validation."
                    }
                    if let parsedPlan {
                        let proposed = Set(parsedPlan.operations.map { $0.currentPath })
                        let unproposed = selectedFilePaths.subtracting(proposed)
                        if !unproposed.isEmpty {
                            cleanMarkdown += "\n\n> [!NOTE]\n> \(unproposed.count) checked file(s) weren't included in the proposal. Run the tool again to propose moves for them."
                        }
                    } else if !extracted.operations.isEmpty {
                        cleanMarkdown += "\n\n> [!ERROR]\n> The proposed operations were rejected because no checked file matched a valid, safe destination. Check the files and destination folders, then run the tool again."
                    }
                } else if let proposed = result.fileOperationPlan {
                    let valid = proposed.operations.filter { operation in
                        PlanOperationParser.validate(
                            operation: PlanOperationEntry(from: operation.currentPath, to: operation.proposedPath, reason: operation.reason),
                            checkedPaths: selectedFilePaths,
                            directory: workspace.url
                        ) == nil
                    }
                    let skipped = proposed.operations.count - valid.count
                    if !valid.isEmpty {
                        parsedPlan = FileOperationPlan(
                            summary: "\(valid.count) move(s) proposed. Nothing has been changed until you approve.",
                            operations: valid,
                            requiresApproval: true
                        )
                    } else {
                        parsedPlan = nil
                    }
                    if skipped > 0 {
                        cleanMarkdown += "\n\n> [!NOTE]\n> \(skipped) proposed move(s) were skipped because they failed validation."
                    }
                }
            }
            activeTask.resultMarkdown = cleanMarkdown
            activeTask.citations = result.citations
            activeTask.actionItems = result.actionItems
            activeTask.fileOperationPlan = parsedPlan
            let awaitingApproval = parsedPlan != nil
            activeTask.status = awaitingApproval ? .needsReview : .complete
            if let existing = sessionTasks.firstIndex(where: { $0.id == activeTask.id }) {
                sessionTasks[existing] = activeTask
            } else {
                sessionTasks.append(activeTask)
            }
            tasksByContext[contextKey] = sessionTasks
            if awaitingApproval {
                activeTask.activity.append(ActivityEvent(title: "Plan approval requested", detail: "\(parsedPlan!.operations.count) move(s) proposed. Approve or reject in the chat.", state: .review))
            } else {
                activeTask.activity.append(ActivityEvent(title: "Tool completed", detail: "\(result.citations.count) citations prepared.", state: .done))
            }
            if template.outputMode == .filePlan, parsedPlan == nil {
                activeTask.activity.append(ActivityEvent(title: "No machine-readable plan", detail: "No valid operations were proposed, so no moves could be planned.", state: .failed))
                if showResult, let markdown = activeTask.resultMarkdown {
                    appendMessage(ChatMessage(role: .assistant, markdown: markdown))
                }
            } else if showResult, let markdown = activeTask.resultMarkdown {
                var message = ChatMessage(role: .assistant, markdown: markdown, citations: result.citations)
                if let parsedPlan {
                    message.filePlan = parsedPlan
                }
                appendMessage(message)
            }
            persist()
        } catch is CancellationError {
            markRunningStepsFailed()
            activeTask.status = .cancelled
            activeTask.activity.append(ActivityEvent(title: "Cancelled", detail: "The active tool stopped before completion.", state: .failed))
        } catch LocalModelError.contextSizeExceeded {
            markRunningStepsFailed()
            activeTask.status = .failed
            activeTask.activity.append(ActivityEvent(title: "Context window exceeded", detail: "The request grew past the model's context window.", state: .failed))
            if showResult {
                appendMessage(ChatMessage(role: .assistant, markdown: "> [!ERROR]\n> **\(template.title) failed**\n\nThe request grew past the model's context window. Check fewer files or clear this chat, then run again."))
            }
        } catch {
            markRunningStepsFailed()
            activeTask.status = .failed
            activeTask.activity.append(ActivityEvent(title: "Tool failed", detail: error.localizedDescription, state: .failed))
            if showResult {
                appendMessage(ChatMessage(role: .assistant, markdown: "> [!ERROR]\n> **\(template.title) failed**\n\n\(error.localizedDescription)\n\nCheck fewer files if the context window was exceeded, then run again."))
            }
        }

        isExecutingTask = false
        executionTask = nil
    }

    private func markRunningStepDone(_ title: String) {
        guard let index = activeTask.activity.lastIndex(where: { $0.title == title && $0.state == .running }) else { return }
        activeTask.activity[index].state = .done
    }

    private func markRunningStepsFailed() {
        for index in activeTask.activity.indices where activeTask.activity[index].state == .running {
            activeTask.activity[index].state = .failed
        }
    }

    func rejectPlan(messageID: UUID) {
        guard let messageIndex = indexOfMessage(messageID),
              chatThreads[messageIndex.thread].messages[messageIndex.message].filePlan != nil,
              chatThreads[messageIndex.thread].messages[messageIndex.message].planApproved == nil
        else { return }
        chatThreads[messageIndex.thread].messages[messageIndex.message].planApproved = false
        activeTask.activity.append(ActivityEvent(title: "Plan rejected", detail: "No files were changed.", state: .failed))
        persist()
    }

    func approvePlan(messageID: UUID, destinations: [String: String]) {
        guard permissions.write,
              let workspace,
              let messageIndex = indexOfMessage(messageID) else { return }
        let message = chatThreads[messageIndex.thread].messages[messageIndex.message]
        guard let plan = message.filePlan, message.planApproved == nil, !planApprovalsInFlight.contains(messageID) else { return }
        planApprovalsInFlight.insert(messageID)

        let destinationMap = plan.operations.reduce(into: [String: String]()) { result, op in
            let dest = (destinations[op.currentPath] ?? op.proposedPath).trimmingCharacters(in: .whitespacesAndNewlines)
            if !dest.isEmpty { result[op.currentPath] = dest }
        }
        activeTask.activity.append(ActivityEvent(title: "Applying plan", detail: "Moving \(destinationMap.count) file(s) inside \(workspace.name).", state: .running))
        persist()

        let root = workspace.url
        executionTask = Task {
            defer { planApprovalsInFlight.remove(messageID) }
            guard !Task.isCancelled else {
                isExecutingTask = false
                executionTask = nil
                return
            }
            let checked = selectedFilePaths
            let outcomes = Self.applyOperations(destinationMap, in: root, checkedPaths: checked)
            let failed = outcomes.filter { $0.error != nil }
            activeTask.status = failed.isEmpty ? .complete : .failed
            activeTask.activity.append(ActivityEvent(
                title: failed.isEmpty ? "Plan applied" : "Plan partially applied",
                detail: "\(outcomes.count - failed.count) of \(outcomes.count) move(s) succeeded.",
                state: failed.isEmpty ? .done : .failed
            ))
            if failed.isEmpty {
                appendMessage(ChatMessage(role: .assistant, markdown: "> [!SUCCESS]\n> **Plan applied.** Moved \(outcomes.count) file(s) into new folders. Workspace re-scanned."))
            } else {
                let detail = failed.map { outcome -> String in
                    let dest = outcome.to ?? "?"
                    let reason = outcome.error ?? "failed"
                    return "- \(outcome.from) → \(dest): \(reason)"
                }.joined(separator: "\n")
                appendMessage(ChatMessage(role: .assistant, markdown: "> [!ERROR]\n> Applied \(outcomes.count - failed.count) of \(outcomes.count) move(s).\n\n\(detail)"))
            }
            // Record approval only after the moves have run: if the app crashes
            // mid-apply, the plan stays unapproved and can be retried instead of
            // falsely reading as "approved and applied".
            setPlanApproved(messageID: messageID, true)
            if !Task.isCancelled {
                await rescanAndReindexWorkspace()
            }
            persist()
            isExecutingTask = false
            executionTask = nil
        }
    }

    private func setPlanApproved(messageID: UUID, _ approved: Bool) {
        guard let messageIndex = indexOfMessage(messageID) else { return }
        chatThreads[messageIndex.thread].messages[messageIndex.message].planApproved = approved
    }

    private struct MessageIndex {
        var thread: Int
        var message: Int
    }

    private func indexOfMessage(_ id: UUID) -> MessageIndex? {
        guard let t = chatThreads.firstIndex(where: { $0.id == activeChatID }),
              let m = chatThreads[t].messages.firstIndex(where: { $0.id == id }) else { return nil }
        return MessageIndex(thread: t, message: m)
    }

    private struct MoveOutcome {
        var from: String
        var to: String?
        var error: String?
    }

    private static func applyOperations(_ destinations: [String: String], in root: URL, checkedPaths: Set<String>) -> [MoveOutcome] {
        var outcomes: [MoveOutcome] = []
        let fm = FileManager.default
        for (fromPath, toFolder) in destinations.sorted(by: { $0.key < $1.key }) {
            guard checkedPaths.contains(fromPath) else {
                outcomes.append(MoveOutcome(from: fromPath, to: toFolder, error: "not a checked file"))
                continue
            }
            guard let destFolder = PlanOperationParser.resolveDestination(toFolder, in: root) else {
                outcomes.append(MoveOutcome(from: fromPath, to: toFolder, error: "destination outside the workspace"))
                continue
            }
            let source = root.appendingPathComponent(fromPath)
            guard fm.fileExists(atPath: source.path) else {
                outcomes.append(MoveOutcome(from: fromPath, to: toFolder, error: "source does not exist"))
                continue
            }
            guard PlanOperationParser.sourceIsInsideWorkspace(source, root: root) else {
                outcomes.append(MoveOutcome(from: fromPath, to: toFolder, error: "source is outside the workspace"))
                continue
            }
            if PlanOperationParser.targetExists(source, to: toFolder, root: root) {
                outcomes.append(MoveOutcome(from: fromPath, to: toFolder, error: "destination already exists"))
                continue
            }
            if destFolder.path == source.deletingLastPathComponent().standardizedFileURL.path {
                outcomes.append(MoveOutcome(from: fromPath, to: toFolder, error: "destination already exists"))
                continue
            }
            do {
                let target = destFolder.appendingPathComponent(source.lastPathComponent)
                guard PlanOperationParser.sourceIsInsideWorkspace(source, root: root) else {
                    outcomes.append(MoveOutcome(from: fromPath, to: target.path, error: "source is outside the workspace (TOCTOU check)"))
                    continue
                }
                try fm.createDirectory(at: destFolder, withIntermediateDirectories: true)
                try fm.moveItem(at: source, to: target)
                outcomes.append(MoveOutcome(from: fromPath, to: target.path))
            } catch {
                let target = destFolder.appendingPathComponent(source.lastPathComponent)
                outcomes.append(MoveOutcome(from: fromPath, to: target.path, error: error.localizedDescription))
            }
        }
        return outcomes
    }

    private func rescanAndReindexWorkspace() async {
        guard !Task.isCancelled, let workspace else { return }
        let scanned = scanner.scan(url: workspace.url)
        self.workspace = scanned
        selectedFilePaths = selectedFilePaths.filter { path in
            scanned.files.contains { $0.relativePath == path }
        }
        indexSummary = nil
        indexStatusMessage = "Re-indexing after file changes."
        let filtered = workspaceWithCheckedFiles(scanned)
        let indexTask = Task.detached(priority: .userInitiated) {
            let service = TaskExecutionService()
            return try service.buildIndex(for: filtered, includeGitSnapshot: false)
        }
        let summary = try? await indexTask.value
        if let summary {
            indexSummary = summary
        }
        indexStatusMessage = nil
        persist()
    }

    private func indexAndSelectOffMain(template: TaskTemplate, workspace: Workspace, budget: ContextBudget) async throws -> IndexedContext {
        let filteredWorkspace = workspaceWithCheckedFiles(workspace)
        let task = Task.detached(priority: .userInitiated) {
            let service = TaskExecutionService()
            let summary = try service.buildIndex(for: filteredWorkspace, includeGitSnapshot: false)
            try Task.checkCancellation()
            let selected = try service.selectChunks(for: template, workspace: filteredWorkspace, from: summary.chunks, budget: budget)
            return IndexedContext(summary: summary, selectedChunks: selected)
        }

        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func workspaceWithCheckedFiles(_ workspace: Workspace) -> Workspace {
        var summary = WorkspaceSummary()
        let files = workspace.files.filter { selectedFilePaths.contains($0.relativePath) }
        summary.totalFiles = files.count
        summary.totalBytes = files.reduce(0) { $0 + $1.byteCount }
        for file in files {
            summary.counts[file.kind, default: 0] += 1
        }
        return Workspace(url: workspace.url, kind: workspace.kind, files: files, summary: summary, scannedAt: workspace.scannedAt)
    }

    private func groundedWorkspacePrompt(userPrompt: String, taskPrompt: String) -> String {
        let checkedList = checkedFiles.prefix(80).map { "- `\($0.relativePath)`" }.joined(separator: "\n")
        return """
        \(taskPrompt)

        User request: \(userPrompt)

        Use only the retrieved chunks from the checked files below. If the answer is not supported by those chunks, say that the checked files do not contain enough information. Do not use unchecked files or outside knowledge.

        Checked files:
        \(checkedList.isEmpty ? "- None" : checkedList)
        """
    }

    private func makeConversationHistory(from messages: [ChatMessage], budget: ContextBudget, usedByChunks: Int) async -> ConversationHistory {
        let capacity = max(budget.contentBudget - usedByChunks, 0)
        let summaryCeilingTokens = 1400
        var recent: [ChatMessage] = []
        var recentTokens = 0
        var overflowParts: [String] = []
        var overflowTokens = 0

        for message in messages.reversed() {
            if message.role == .assistant && message.isFailed { continue }
            let tokens = Self.estimatedTokens(for: message.markdown)
            if recentTokens + tokens <= capacity || recent.isEmpty {
                recent.append(message)
                recentTokens += tokens
            } else if overflowTokens < summaryCeilingTokens {
                overflowParts.append("[\(message.role == .user ? "User" : "Assistant")] \(message.markdown)")
                overflowTokens += tokens
            }
        }

        guard !overflowParts.isEmpty else {
            return ConversationHistory(messages: recent.reversed(), summary: nil)
        }

        let summaryPrompt = """
        Summarize the earlier conversation below into concise notes for continuing it. Preserve exact names, numbers, dates, identifiers, and quoted strings verbatim. Never invent facts, and do not drop a fact just because it was not mentioned recently.

        \(overflowParts.reversed().joined(separator: "\n\n"))
        """
        let summaryRequest = LocalModelRequest(taskTitle: "Conversation Summary", prompt: summaryPrompt, chunks: [], contextBudget: budget, outputMode: .markdown)
        if let summary = try? await modelClient.respond(to: summaryRequest).markdown,
           !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ConversationHistory(messages: recent.reversed(), summary: summary)
        }
        return ConversationHistory(messages: recent.reversed(), summary: nil)
    }

    private func activateOrCreateChat(contextKey: String, title: String) {
        if let existing = chatThreads
            .filter({ $0.contextKey == contextKey })
            .max(by: { $0.updatedAt < $1.updatedAt }) {
            activeChatID = existing.id
        } else {
            let thread = ChatThread(contextKey: contextKey, title: title)
            chatThreads.append(thread)
            activeChatID = thread.id
        }
    }

    private func appendMessage(_ message: ChatMessage) {
        guard let index = chatThreads.firstIndex(where: { $0.id == activeChatID }) else { return }
        chatThreads[index].messages.append(message)
        chatThreads[index].updatedAt = Date()
        persist()
    }

    private func autoTitleCurrentChat(from message: String) {
        guard let index = chatThreads.firstIndex(where: { $0.id == activeChatID }),
              !chatThreads[index].isTitleEdited,
              chatThreads[index].messages.count <= 1
        else { return }
        let words = message.split { $0.isWhitespace || $0.isNewline }.prefix(7).joined(separator: " ")
        chatThreads[index].title = words.isEmpty ? "New chat" : words
    }

    private func remember(workspace: Workspace) {
        let displayName = workspaceNameOverrides[workspace.path] ?? workspace.name
        let recent = RecentWorkspace(
            name: displayName,
            path: workspace.path,
            kind: workspace.kind,
            openedAt: Date(),
            totalFiles: workspace.summary.totalFiles
        )
        recentWorkspaces.removeAll { $0.path == workspace.path }
        recentWorkspaces.insert(recent, at: 0)
        recentWorkspaces = Array(recentWorkspaces.prefix(24))
    }

    private func cancelChatForSwitch() {
        chatTask?.cancel()
        chatTask = nil
        executionTask?.cancel()
        executionTask = nil
        isChatting = false
        isExecutingTask = false
    }

    private func persist() {
        persistenceStore.save(
            StudioPersistenceSnapshot(
                recentWorkspaces: recentWorkspaces,
                chatThreads: chatThreads,
                savedResponses: savedResponses,
                tasksByContext: tasksByContext,
                mcpServers: mcpServers,
                workspaceMCPSettings: workspaceMCPSettings,
                workspaceNameOverrides: workspaceNameOverrides,
                workspacePermissions: workspacePermissionOverrides
            )
        )
    }

    func planSteps(for template: TaskTemplate) -> [String] {
        switch template.title {
        case "Summarize":
            ["Read checked files only.", "Chunk content under the context budget.", "Retrieve representative passages.", "Create a Markdown summary with citations."]
        case "Extract Actions":
            ["Search checked files for task-like language.", "Normalize owner, date, source, and confidence.", "Group duplicates and unresolved decisions.", "Render a reviewable Markdown table."]
        case "Organize Files":
            ["Read names, metadata, and safe snippets from checked files.", "Propose folders and renames without touching files.", "Show a review plan.", "Apply only after explicit approval in a later workflow."]
        case "Explain Codebase":
            ["Detect package files and entry points among checked files.", "Summarize architecture and workflows.", "Call out tests, scripts, and setup commands.", "Cite the files used."]
        default:
            ["Collect checked workspace context.", "Apply schema-guided extraction.", "Validate records before export.", "Return copyable Markdown or JSON."]
        }
    }

    private func polishMarkdown(_ markdown: String) -> String {
        ChatMarkdownFormatter.polish(markdown)
    }

    private func chatFriendlyMarkdown(_ markdown: String) -> String {
        ChatMarkdownFormatter.chatFriendly(markdown)
    }
}

private struct IndexedContext: Sendable {
    var summary: ChunkIndexSummary
    var selectedChunks: [TextChunk]
}
