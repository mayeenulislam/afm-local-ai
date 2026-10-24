import AppKit
import SwiftUI

func appModelLogo() -> NSImage? {
    let name = "foundationmodel-96x96_2x"
    if let url = Bundle.main.url(forResource: name, withExtension: "png")
        ?? Bundle.module.url(forResource: name, withExtension: "png") {
        return NSImage(contentsOf: url)
    }
    return nil
}

struct LogoImage: View {
    var size: CGFloat
    var body: some View {
        if let logo = appModelLogo() {
            Image(nsImage: logo)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            AFMGradientIcon(symbol: "globe.americas.fill", size: size, symbolSize: size / 2)
        }
    }
}

struct SidebarView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showModelDiagnostics = false
    @State private var cachedTree: (key: String, tree: FileTree)?

    private func fileTree(for workspace: Workspace) -> FileTree {
        let key = "\(workspace.url.path)|\(workspace.scannedAt.timeIntervalSince1970)"
        if let cachedTree, cachedTree.key == key {
            return cachedTree.tree
        }
        let tree = FileTree(workspace: workspace)
        cachedTree = (key, tree)
        return tree
    }

    var body: some View {
        Group {
            switch appState.mode {
            case .dashboard:
                EmptyView()
            case .generalChat:
                generalChatSidebar
            case .workspace:
                workspaceSidebar
            }
        }
        .background(Color.afmSidebar)
        .sheet(isPresented: $showModelDiagnostics) {
            ModelDiagnosticsView()
                .environmentObject(appState)
        }
    }

    // MARK: - General Chat Sidebar

    private var generalChatSidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                AFMSectionLabel(text: "General Chats")
                Spacer()
                Button {
                    appState.createChatForCurrentContext()
                } label: {
                    Label("New Chat", systemImage: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.afmBlue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.afmBlueLight, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .overlay(alignment: .bottom) { Divider() }

            ScrollView {
                LazyVStack(spacing: 2) {
                    if appState.contextChatThreads.isEmpty {
                        VStack(spacing: 6) {
                            Text("No chats yet")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Start a conversation to begin.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 24)
                        .frame(maxWidth: .infinity)
                    } else {
                        ForEach(appState.contextChatThreads) { thread in
                            generalChatRow(thread)
                        }
                    }
                }
                .padding(8)
            }

            modelSpecsCard
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.afmSurface)
                .overlay(alignment: .top) { Divider() }
        }
    }

    private func generalChatRow(_ thread: ChatThread) -> some View {
        let isActive = appState.activeChat?.id == thread.id
        return HStack(spacing: 6) {
            Button {
                appState.activateChat(thread)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isActive ? "bubble.left.and.bubble.right.fill" : "bubble.left")
                        .font(.system(size: 12))
                        .foregroundStyle(isActive ? Color.afmBlue : Color.secondary)
                    Text(thread.title)
                        .font(.system(size: 12, weight: isActive ? .semibold : .medium))
                        .foregroundStyle(isActive ? Color.afmBlue : Color.primary.opacity(0.8))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isActive {
                Button {
                    appState.deleteChat(thread)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .padding(2)
                }
                .buttonStyle(.plain)
                .help("Delete chat")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(isActive ? Color.afmBlueLight : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            if isActive {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.afmBlue.opacity(0.35))
            }
        }
    }

    // MARK: Model Specs Card

    private var modelSpecsCard: some View {
        Button {
            showModelDiagnostics = true
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    LogoImage(size: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(appState.modelStatus.title)
                            .font(.system(size: 12, weight: .bold))
                        Text(appState.modelStatus.detail)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Text(appState.modelStatus.isOnDeviceProvider
                     ? "\(appState.modelStatus.contextWindow.formatted()) tok • Zero network traffic"
                     : "Mock Mode • responses simulated on-device")
                    .font(.afmMono(10))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Show model diagnostics")
    }

    // MARK: - Workspace Sidebar

    private var workspaceSidebar: some View {
        VStack(spacing: 0) {
            if let workspace = appState.workspace {
                List {
                    Section {
                        WorkspaceHeader(workspace: workspace)
                        RAGInfoButton()
                    }

                    Section {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(fileTree(for: workspace).roots) { node in
                                    FileTreeNodeView(node: node)
                                }
                            }
                        }
                        .frame(maxHeight: 260)
                    } header: {
                        let isAll = !workspace.enterableFiles.isEmpty && appState.selectedFilePaths.count == workspace.enterableFiles.count
                        let isNone = appState.selectedFilePaths.isEmpty
                        HStack(spacing: 8) {
                            Button {
                                appState.toggleAllFiles(!isAll)
                            } label: {
                                Image(systemName: isAll ? "checkmark.square.fill" : (isNone ? "square" : "minus.square.fill"))
                                    .foregroundStyle(isAll ? .green : (isNone ? .secondary : .orange))
                            }
                            .buttonStyle(.plain)
                            .help(isAll ? "Remove all files from context" : "Include all files in context")
                            .accessibilityLabel(isAll ? "Remove all files from context" : "Include all files in context")
                            Text("Files")
                            Spacer()
                            Button {
                                appState.expandedDirectories.removeAll()
                            } label: {
                                Image(systemName: "minus.square")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Collapse all folders")
                            .accessibilityLabel("Collapse all folders")
                            Text("\(appState.selectedFilePaths.count)/\(workspace.enterableFiles.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.trailing, 14)
                        }
                    }

                    Section("Context & Indexes") {
                        ContextBudgetMeter(budget: appState.liveContextBudget, checkedEstimate: appState.checkedContextTokens)
                        contextContent
                    }
                }
                .listStyle(.sidebar)
                .overlay {
                    if appState.isScanning {
                        ProgressView("Scanning workspace...")
                            .padding(18)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }

    private var contextContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let summary = appState.indexSummary {
                PermissionRow(title: "Chunks", state: "\(summary.chunks.count)", tint: .blue)
                PermissionRow(title: "Indexed files", state: "\(summary.indexedFiles)", tint: .green)
                PermissionRow(title: "Skipped files", state: "\(summary.skippedFiles)", tint: .orange)
                if let semantic = summary.semanticSummary {
                    PermissionRow(title: "Retrieval", state: semantic.isAvailable ? "Semantic" : "FTS", tint: semantic.isAvailable ? .green : .secondary)
                    PermissionRow(title: "Embedded chunks", state: "\(semantic.embeddedChunks)", tint: .blue)
                }
            } else {
                Label("No index for this context yet", systemImage: "tray")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Chat or run a tool. Only checked files are indexed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let message = appState.indexStatusMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct RAGInfoButton: View {
    @EnvironmentObject private var appState: AppState
    @State private var isPresented = false

    var body: some View {
        if let workspace = appState.workspace {
            Button {
                isPresented.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: workspace.kind.symbol)
                        .font(.caption)
                    Text(workspace.kind.rawValue)
                        .font(.caption)
                    Spacer()
                    Image(systemName: "info.circle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(6)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isPresented, arrowEdge: .trailing) {
                RAGInfoView(appState: appState, showWorkspaceName: true)
                    .padding(14)
                    .frame(minWidth: 240)
            }
            .help("\(workspace.kind.rawValue) workspace — click to view file breakdown (Markdown / Code / PDF / Docs / Data)")
        }
    }
}

private struct WorkspaceHeader: View {
    var workspace: Workspace
    @EnvironmentObject private var appState: AppState
    @State private var showSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.afmBlueLight)
                        .frame(width: 40, height: 40)
                    Image(systemName: workspace.kind.symbol)
                        .font(.system(size: 16))
                        .foregroundStyle(Color.afmBlue)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(appState.workspaceDisplayName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(workspace.kind.rawValue)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    showSettings.toggle()
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .background(Color.afmCard, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(Color.afmBorder)
                        }
                }
                .buttonStyle(.plain)
                .help("Workspace Settings")
            }
            HStack(spacing: 5) {
                Image(systemName: "folder")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                Text(workspace.path)
                    .font(.afmMono(10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
        }
        .padding(.top, 6)
        .padding(.bottom, 2)
        .sheet(isPresented: $showSettings) {
            WorkspaceSettingsSheet(fallbackName: appState.workspace?.name ?? "")
                .environmentObject(appState)
        }
    }
}

struct WorkspaceSettingsSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    var workspacePath: String? = nil
    var fallbackName = ""
    @State private var selectedTab: SettingsTab = .permissions
    @State private var showingMCPServers = false
    @State private var initialized = false
    @State private var draftPermissions = WorkspacePermissions.askEveryTime
    @State private var draftName = ""
    @State private var draftEnabledServerIDs: Set<UUID> = []

    private var targetPath: String? { workspacePath ?? appState.workspace?.path }

    private var resolvedDisplayName: String {
        guard let path = targetPath else { return appState.workspaceDisplayName }
        return appState.workspaceDisplayName(for: path, fallback: fallbackName)
    }

    private var enabledServerIDs: Set<UUID> {
        guard let path = targetPath else { return [] }
        return Set(appState.mcpSettings(for: path).enabledServerIDs)
    }

    private var draftBinding: (WritableKeyPath<WorkspacePermissions, Bool>) -> Binding<Bool> {
        { keyPath in
            Binding(
                get: { draftPermissions[keyPath: keyPath] },
                set: { draftPermissions[keyPath: keyPath] = $0 }
            )
        }
    }

    private func resetToDefaults() {
        draftPermissions = WorkspacePermissions.askEveryTime
        draftName = resolvedDisplayName
        seedEnabledServers()
    }

    private func seedEnabledServers() {
        draftEnabledServerIDs = enabledServerIDs
    }

    private func save() {
        appState.savePermissions(draftPermissions, for: targetPath)
        appState.saveWorkspaceDisplayName(draftName, path: targetPath)
        for server in appState.mcpServers {
            let wanted = draftEnabledServerIDs.contains(server.id)
            if wanted != appState.isMCPServerEnabledInWorkspace(server.id, path: targetPath) {
                appState.setMCPServerEnabledInWorkspace(wanted, serverID: server.id, path: targetPath)
            }
        }
        dismiss()
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            VStack(alignment: .leading, spacing: 14) {
                workspaceTargetField
                if appState.mcpTransportReady {
                    SettingsSegmentsView(selection: $selectedTab,
                                         mcpActive: !enabledServerIDs.isEmpty)
                    switch selectedTab {
                    case .permissions:
                        permissionsContent
                    case .mcp:
                        mcpContent
                    }
                } else {
                    permissionsContent
                }
            }
            .padding(16)
            .frame(width: 420, alignment: .leading)
            footer
        }
        .frame(maxWidth: 420)
        .onAppear {
            guard !initialized else { return }
            initialized = true
            draftPermissions = appState.permissions(for: targetPath)
            draftName = resolvedDisplayName
            seedEnabledServers()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.afmBlue)
                .frame(width: 24, height: 24)
                .background(Color.afmBlueLight, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            Text("Workspace Settings")
                .font(.system(size: 13, weight: .bold))
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background(Color.afmInput, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.afmSurface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.afmBorder).frame(height: 1)
        }
    }

    private var workspaceTargetField: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Workspace Name")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("Workspace name", text: $draftName)
                .textFieldStyle(.roundedBorder)
                .font(.afmMono(12))
        }
    }

    private var permissionsContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Granular Capabilities")
                    .font(.system(size: 12, weight: .bold))
                VStack(spacing: 0) {
                    PermissionToggle(title: "Read project files", systemImage: "eye", isOn: draftBinding(\.read))
                        .padding(.vertical, 8)
                    settingsDivider
                    PermissionToggle(title: "Write & modify files", systemImage: "pencil", isOn: draftBinding(\.write))
                        .padding(.vertical, 8)
                    settingsDivider
                    PermissionToggle(title: "Delete files", systemImage: "trash", isOn: draftBinding(\.delete))
                        .padding(.vertical, 8)
                    settingsDivider
                    PermissionToggle(title: "Shell commands", systemImage: "terminal", isOn: draftBinding(\.shell))
                        .padding(.vertical, 8)
                    settingsDivider
                    PermissionToggle(title: "Network egress", systemImage: "network", isOn: draftBinding(\.network))
                        .padding(.vertical, 8)
                }
                .padding(.horizontal, 12)
                .background(Color.afmInput.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.afmBorder)
                }
            }
        }
    }

    private var settingsDivider: some View {
        Rectangle().fill(Color.afmBorder).frame(height: 1)
    }

    private var mcpContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Configured MCP Servers")
                    .font(.system(size: 12, weight: .bold))
                Spacer()
                Button {
                    showingMCPServers = true
                } label: {
                    Label("Add MCP Server", systemImage: "plus")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.afmBlue)
                .controlSize(.small)
            }

            if appState.mcpServers.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No MCP servers configured")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("Add a stdio or Streamable HTTP server to expose its tools to this workspace. Transport is configured globally; connection and tool discovery are planned next.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                VStack(spacing: 6) {
                    ForEach(appState.mcpServers) { server in
                        let enabled = draftEnabledServerIDs.contains(server.id)
                        HStack(spacing: 10) {
                            Circle()
                                .fill(enabled ? Color.green : Color.secondary.opacity(0.4))
                                .frame(width: 7, height: 7)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(server.name)
                                    .font(.system(size: 12, weight: .bold))
                                Text(server.detailLine)
                                    .font(.afmMono(9))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if enabled {
                                Text("Active in RAG")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.green)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Color.green.opacity(0.12), in: Capsule())
                                    .overlay {
                                        Capsule().strokeBorder(Color.green.opacity(0.35))
                                    }
                            }
                            Toggle("", isOn: Binding(
                                get: { enabled },
                                set: { newValue in
                                    if newValue {
                                        draftEnabledServerIDs.insert(server.id)
                                    } else {
                                        draftEnabledServerIDs.remove(server.id)
                                    }
                                }
                            ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .accessibilityLabel("Enable \(server.name) in this workspace")
                        }
                        .padding(10)
                        .background(Color.afmCard, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.afmBorder)
                        }
                    }
                }

                if !draftEnabledServerIDs.isEmpty {
                    let hasRemoteEnabled = draftEnabledServerIDs.contains { id in
                        appState.mcpServers.first(where: { $0.id == id })?.transport.isRemote == true
                    }
                    if hasRemoteEnabled {
                        Label("Remote servers can send workspace context off this Mac.", systemImage: "exclamationmark.triangle")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                settingsDivider
                HStack {
                    Text("Local servers")
                    Spacer()
                    Text("\(appState.mcpStatus.localServers)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.green)
                }
                HStack {
                    Text("Remote servers")
                    Spacer()
                    Text("\(appState.mcpStatus.remoteServers)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.orange)
                }
            }
        }
        .sheet(isPresented: $showingMCPServers) {
            MCPServerManagerSheet()
                .environmentObject(appState)
        }
    }

    private var footer: some View {
        HStack {
            Button("Reset to Defaults") {
                resetToDefaults()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.red)
            Spacer()
            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Button("Save Settings") {
                save()
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.afmBlue)
            .controlSize(.small)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.afmSurface)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.afmBorder).frame(height: 1)
        }
    }
}

private struct SettingsSegmentsView: View {
    @Binding var selection: SettingsTab
    var mcpActive: Bool

    var body: some View {
        HStack(spacing: 4) {
            segment(.permissions, title: "Permissions & Sandbox", symbol: "checkmark.shield")
            segment(.mcp, title: "Model Context Protocol", symbol: nil, dot: mcpActive)
        }
        .padding(4)
        .background(Color.afmInput, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func segment(_ tab: SettingsTab, title: String, symbol: String?, dot: Bool = false) -> some View {
        Button {
            selection = tab
        } label: {
            HStack(spacing: 5) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 9, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 11, weight: selection == tab ? .semibold : .regular))
                if dot {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                }
            }
            .foregroundStyle(selection == tab ? Color.primary : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background {
                if selection == tab {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.afmCard)
                        .shadow(color: .black.opacity(0.08), radius: 1, y: 0.5)
                }
            }
            .overlay {
                if selection == tab {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.afmBorder.opacity(0.6))
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private enum SettingsTab: String, CaseIterable {
    case permissions
    case mcp
}

struct FileTreeNode: Identifiable {
    let id = UUID()
    let name: String
    let directory: String?
    let file: WorkspaceFile?
    var descendantCount = 0
    var children: [FileTreeNode] = []

    var isFolder: Bool { file == nil }
}

struct FileTree {
    private(set) var roots: [FileTreeNode] = []

    init(workspace: Workspace) {
        let files = workspace.enterableFiles
        var dirs = Set<String>()
        for file in files {
            if let slash = file.relativePath.lastIndex(of: "/") {
                var dir = String(file.relativePath[file.relativePath.startIndex..<slash])
                while !dir.isEmpty {
                    dirs.insert(dir)
                    if let slash2 = dir.lastIndex(of: "/") {
                        dir = String(dir[dir.startIndex..<slash2])
                    } else {
                        break
                    }
                }
            }
        }
        let filesByDir = Dictionary(grouping: files) { file -> String? in
            if let slash = file.relativePath.lastIndex(of: "/") {
                return String(file.relativePath[file.relativePath.startIndex..<slash])
            }
            return nil
        }
        let subdirs = Dictionary(grouping: dirs) { dir -> String? in
            if let slash = dir.lastIndex(of: "/") {
                return String(dir[dir.startIndex..<slash])
            }
            return nil
        }

        var descendantCounts: [String: Int] = [:]
        for file in files {
            guard let slash = file.relativePath.lastIndex(of: "/") else { continue }
            var dir = String(file.relativePath[file.relativePath.startIndex..<slash])
            while !dir.isEmpty {
                descendantCounts[dir, default: 0] += 1
                if let slash2 = dir.lastIndex(of: "/") {
                    dir = String(dir[dir.startIndex..<slash2])
                } else {
                    break
                }
            }
        }

        func node(forDirectory dir: String) -> FileTreeNode {
            let name = dir.split(separator: "/").last.map(String.init) ?? dir
            var children: [FileTreeNode] = []
            for sub in (subdirs[dir] ?? []).sorted() {
                children.append(node(forDirectory: sub))
            }
            for file in (filesByDir[dir] ?? []).sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) {
                children.append(FileTreeNode(name: file.name, directory: nil, file: file))
            }
            return FileTreeNode(name: name, directory: dir, file: nil, descendantCount: descendantCounts[dir] ?? 0, children: children)
        }

        var roots: [FileTreeNode] = []
        for dir in (subdirs[nil] ?? []).sorted() {
            roots.append(node(forDirectory: dir))
        }
        for file in (filesByDir[nil] ?? []).sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) {
            roots.append(FileTreeNode(name: file.name, directory: nil, file: file))
        }
        self.roots = roots
    }
}

private struct FileTreeNodeView: View {
    @EnvironmentObject private var appState: AppState
    let node: FileTreeNode

    private var isExpanded: Bool {
        if let directory = node.directory {
            return appState.expandedDirectories.contains(directory)
        }
        return false
    }

    private var collapseHelpText: String {
        (isExpanded ? "Collapse" : "Expand") + " folder · ⌥/⌘-click to collapse or expand all sub-folders"
    }

    private var folderCheckboxLabel: String {
        switch appState.directoryState(node.directory!) {
        case .some(true): "Exclude all files in \(node.name)"
        case .some(false), .none: "Include all files in \(node.name)"
        }
    }

    private func toggleFolderExpansion() {
        if NSEvent.modifierFlags.contains(.option) || NSEvent.modifierFlags.contains(.command) {
            appState.toggleDirectoryExpandedRecursively(node.directory!)
        } else {
            appState.toggleDirectoryExpanded(node.directory!)
        }
    }

    var body: some View {
        if node.isFolder {
            folderColumn
        } else if let file = node.file {
            HStack(spacing: 4) {
                Image(systemName: "chevron.right")
                    .opacity(0)
                    .font(.caption2)
                    .frame(width: 16)
                FileCheckboxRow(
                    file: file,
                    isChecked: appState.selectedFilePaths.contains(file.relativePath),
                    isSelected: appState.selectedFile?.relativePath == file.relativePath
                )
            }
        }
    }

    private var folderColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Button {
                    toggleFolderExpansion()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .foregroundStyle(.secondary)
                        .frame(width: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(collapseHelpText)
                .accessibilityLabel((isExpanded ? "Collapse" : "Expand") + " \(node.name)")

                Button {
                    let on = appState.directoryState(node.directory!) != true
                    appState.toggleDirectory(node.directory!, isOn: on)
                } label: {
                    folderCheckboxIcon
                        .frame(width: 18)
                }
                .buttonStyle(.plain)
                .help("Include / exclude this folder's files")
                .accessibilityLabel(folderCheckboxLabel)

                Button {
                    toggleFolderExpansion()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "folder")
                            .foregroundStyle(.blue)
                            .frame(width: 18)
                        Text(node.name)
                            .lineLimit(1)
                        Spacer()
                        Text("\(node.descendantCount)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(collapseHelpText)
                .accessibilityLabel("\(node.name), \(node.descendantCount) files, \(isExpanded ? "expanded" : "collapsed")")
            }
            .padding(.vertical, 3)

            if isExpanded {
                // ponytail: eager children render — a single explicitly-expanded folder with
                // tens of thousands of readable files will still stall one layout pass.
                // Upgrade path: render children in an inner LazyVStack when folder sizes demand it.
                ForEach(node.children) { child in
                    FileTreeNodeView(node: child)
                        .padding(.leading, 12)
                }
            }
        }
    }

    @ViewBuilder private var folderCheckboxIcon: some View {
        switch appState.directoryState(node.directory!) {
        case .some(true):
            Image(systemName: "checkmark.square.fill").foregroundStyle(.green)
        case .none:
            Image(systemName: "minus.square.fill").foregroundStyle(.orange)
        case .some(false):
            Image(systemName: "square").foregroundStyle(.secondary)
        }
    }
}

private struct FileCheckboxRow: View {
    @EnvironmentObject var appState: AppState
    let file: WorkspaceFile
    var isChecked: Bool
    var isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Button {
                appState.toggleFile(file, isOn: !isChecked)
            } label: {
                Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isChecked ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .help(isChecked ? "Remove from context" : "Include in context")
            .accessibilityLabel(isChecked ? "Remove \(file.name) from context" : "Include \(file.name) in context")

            Button {
                appState.selectFile(file)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: file.kind.symbol)
                        .foregroundStyle(file.kind.tint)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(file.name)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(file.relativePath)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        .help(file.relativePath)
    }
}
