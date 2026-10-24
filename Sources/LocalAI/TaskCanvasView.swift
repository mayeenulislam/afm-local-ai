import AppKit
import SwiftUI

struct TaskCanvasView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            switch appState.mode {
            case .dashboard:
                DashboardView()
            case .generalChat, .workspace:
                ChatSurfaceView()
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

private struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showModelDiagnostics = false
    @State private var settingsTarget: RecentWorkspace?
    @State private var filter = ""

    private let columns = [GridItem(.adaptive(minimum: 300), spacing: 14)]

    private var filteredWorkspaces: [RecentWorkspace] {
        guard !filter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return appState.recentWorkspaces }
        return appState.recentWorkspaces.filter {
            $0.name.localizedCaseInsensitiveContains(filter) || $0.path.localizedCaseInsensitiveContains(filter)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                heroSection
                primaryActions
                workspacesSection
                featureSection
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.afmWindow)
        .sheet(isPresented: $showModelDiagnostics) {
            ModelDiagnosticsView()
                .environmentObject(appState)
        }
        .sheet(item: $settingsTarget) { recent in
            WorkspaceSettingsSheet(workspacePath: recent.path, fallbackName: recent.name)
                .environmentObject(appState)
        }
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                LogoImage(size: 70)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Apple Foundation Models (AFM)")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.4)
                        .foregroundStyle(.secondary)
                    Text("Local AI")
                        .font(.system(size: 30, weight: .bold))
                        .tracking(-0.5)
                    Text("A local-first intelligence notebook for your folders, codebases, tools, and notes. Everything runs on this Mac.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }

            HStack(spacing: 6) {
                AFMSpecPill(text: appState.modelStatus.title, dot: appState.modelStatus.isOnDeviceProvider ? .green : .orange)
                AFMSpecPill(text: "\(appState.modelStatus.contextWindow.formatted()) Token Context")
                AFMSpecPill(text: "Checked-File Scope")
                AFMSpecPill(text: "Zero Network Egress")
                Spacer()
                Button {
                    showModelDiagnostics = true
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(appState.modelStatus.isOnDeviceProvider ? Color.green : Color.orange)
                            .frame(width: 6, height: 6)
                        Text("Engine Diagnostics")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text(appState.modelStatus.isOnDeviceProvider ? "\(appState.modelStatus.contextWindow.formatted()) tok" : "Mock Mode")
                            .font(.afmMono(10))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.afmCard, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Color.afmBorder)
                    }
                }
                .buttonStyle(.plain)
                .help("Show model diagnostics")
            }
            .padding(.top, 18)
        }
        .padding(.bottom, 26)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var primaryActions: some View {
        HStack(spacing: 14) {
            Button {
                appState.startGeneralChat()
            } label: {
                HStack(spacing: 14) {
                    AFMOvalIcon(symbol: "bubble.left.and.bubble.right.fill", size: 40, tint: .afmBlue, background: .afmBlueLight)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("General Chat")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Quick conversational session without workspace indexing")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(16)
                .background(Color.afmBlueLight, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.afmBlue, lineWidth: 1.5)
                }
            }
            .buttonStyle(.plain)

            Button {
                appState.openWorkspace()
            } label: {
                HStack(spacing: 14) {
                    AFMOvalIcon(symbol: "folder.badge.plus", size: 40, tint: .white, background: .white.opacity(0.18))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Add Workspace (RAG)")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Index a local directory to work with your files")
                            .font(.system(size: 12))
                            .opacity(0.85)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .semibold))
                        .opacity(0.7)
                }
                .foregroundStyle(.white)
                .padding(16)
                .background(LinearGradient(colors: [.afmBlue, Color(red: 0, green: 0x5B / 255, blue: 0xB5 / 255)], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private var workspacesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    Text("Workspaces")
                        .font(.system(size: 16, weight: .bold))
                    AFMPill(text: "\(appState.recentWorkspaces.count) Active", tint: .secondary, dot: false)
                }
                Spacer()
                if !appState.recentWorkspaces.isEmpty {
                    HStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            TextField("Filter workspaces...", text: $filter)
                                .textFieldStyle(.plain)
                                .font(.system(size: 11))
                                .frame(width: 140)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.afmCard, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(Color.afmBorder)
                        }
                        Button {
                            appState.openWorkspace()
                        } label: {
                            Label("Add Workspace", systemImage: "plus")
                                .font(.system(size: 11, weight: .medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.afmCard, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .strokeBorder(Color.afmBorder)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if appState.recentWorkspaces.isEmpty {
                dashboardEmptyState
            } else if filteredWorkspaces.isEmpty {
                Text("No workspaces match the filter.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 24)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                    ForEach(filteredWorkspaces) { recent in
                        let isCurrent = appState.workspace?.name == recent.name && appState.workspace?.path == recent.path
                        RecentWorkspaceCard(recent: recent, isActive: isCurrent && appState.mode == .workspace) {
                            appState.openRecentWorkspace(recent)
                        } onRemove: {
                            appState.removeRecentWorkspace(recent)
                        } onSettings: {
                            settingsTarget = recent
                        }
                    }
                }
            }
        }
    }

    private var dashboardEmptyState: some View {
        VStack(spacing: 14) {
            AFMOvalIcon(symbol: "folder.badge.plus", size: 46, tint: .afmBlue, background: .afmCard)
            Text("No workspaces opened yet")
                .font(.system(size: 14, weight: .semibold))
            Text("Open a folder once and it will appear here with its local index status, ready for grounded chat and RAG tools.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            HStack(spacing: 8) {
                Button {
                    appState.openWorkspace()
                } label: {
                    Label("Open Existing Folder...", systemImage: "folder")
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .background(Color.afmSurface.opacity(0.5), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.afmBorder, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
        }
    }

    private var featureSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            AFMSectionLabel(text: "Architected for Apple Silicon")
            HStack(alignment: .top, spacing: 14) {
                FeatureCard(symbol: "chevron.left.forwardslash.chevron.right", tint: .green, title: "Codebase Reasoning", text: "Semantic search over Swift, TypeScript, Python, and other checked source files with precise line references.")
                FeatureCard(symbol: "slider.horizontal.below.rectangle", tint: .blue, title: "Dynamic Context Trimming", text: "Retrieval and chunks are budgeted within the on-device context window to prevent overflow.")
                FeatureCard(symbol: "lock.shield.fill", tint: .orange, title: "Strict Sandboxing", text: "Only checked files enter context. Everything stays on this Mac with zero network egress.")
            }
        }
    }
}

private struct FeatureCard: View {
    var symbol: String
    var tint: Color
    var title: String
    var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AFMOvalIcon(symbol: symbol, size: 30, tint: tint, background: tint.opacity(0.12))
            Text(title)
                .font(.system(size: 12, weight: .bold))
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .afmCard(padding: 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RecentWorkspaceCard: View {
    var recent: RecentWorkspace
    var isActive: Bool
    var onOpen: () -> Void
    var onRemove: () -> Void
    var onSettings: () -> Void

    @State private var isHovering = false
    @State private var isHoveringCross = false
    @State private var confirmRemove = false

    private var tint: Color {
        switch recent.kind {
        case .general: .teal
        case .code: .purple
        case .obsidian: .indigo
        case .research: .blue
        case .data: .orange
        case .mixed: .gray
        }
    }

    private var kindLabel: String {
        switch recent.kind {
        case .general: "General"
        case .code: "Codebase"
        case .obsidian: "Markdown Vault"
        case .research: "Research"
        case .data: "Database"
        case .mixed: "Mixed Work"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    AFMOvalIcon(symbol: recent.kind.symbol, size: 32, tint: tint, background: tint.opacity(0.12))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(kindLabel.uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.6)
                            .foregroundStyle(tint)
                        Text(recent.name)
                            .font(.system(size: 13, weight: .bold))
                            .lineLimit(1)
                    }
                    Spacer()
                    AFMIconButton(symbol: "xmark", tint: isHoveringCross ? .red : .black.opacity(0.3), help: "Remove from dashboard") {
                        confirmRemove = true
                    }
                    .onHover { isHoveringCross = $0 }
                }
                Text(recent.path)
                    .font(.afmMono(10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textSelection(.enabled)
                HStack(spacing: 12) {
                    Label("\(recent.totalFiles) files", systemImage: "doc.on.doc")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            }
            Divider()
                .padding(.top, 12)
                .padding(.bottom, 10)
            HStack {
                Text("Opened \(relativeTime(recent.openedAt))")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Spacer()
                HStack(spacing: 6) {
                    AFMIconButton(symbol: "gearshape", tint: .secondary, help: "Workspace settings") {
                        onSettings()
                    }
                    Button(action: onOpen) {
                        HStack(spacing: 3) {
                            Text(isActive ? "Resume Chat" : "Open")
                            Image(systemName: "arrow.right")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isHovering ? .white : Color.afmBlue)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(isHovering ? Color.afmBlue : Color.clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.afmBlue, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .afmCard(padding: 14, radius: 12)
        .frame(maxWidth: .infinity)
        .overlay {
            if isActive {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.afmBlue, lineWidth: 1.5)
            }
        }
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .alert("Remove workspace?", isPresented: $confirmRemove) {
            Button("Remove", role: .destructive) { onRemove() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Remove \"\(recent.name)\" from the dashboard? Its chats and index data stay on disk.")
        }
    }
}

private func relativeTime(_ date: Date) -> String {
    date.formatted(.relative(presentation: .named))
}

private enum RecallDirection {
    case up
    case down
}

private struct ChatSurfaceView: View {
    @EnvironmentObject private var appState: AppState
    @State private var draft = ""
    @State private var recallIndex: Int? = nil
    @State private var recalledDraft = ""

    private var contextDraftHistory: [String] {
        // Per-chat truth: recall candidates are this chat's own user messages, newest last.
        // (No separate draft store — one per context (General / workspace) used to leak drafts across chats.)
        appState.currentMessages
            .filter { $0.role == .user }
            .map(\.markdown)
    }

    private func recall(_ direction: RecallDirection) {
        let history = contextDraftHistory
        guard !history.isEmpty else { return }
        switch direction {
        case .up:
            if recallIndex == nil {
                recalledDraft = draft
                recallIndex = history.count - 1
            } else if let index = recallIndex {
                recallIndex = max(0, index - 1)
            }
            if let index = recallIndex, index < history.count {
                draft = history[index]
            }
        case .down:
            guard let index = recallIndex else { return }
            let next = index + 1
            if next < history.count {
                recallIndex = next
                draft = history[next]
            } else {
                recallIndex = nil
                draft = recalledDraft
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if appState.currentMessages.isEmpty {
                            ChatEmptyView()
                                .padding(.top, 56)
                        }
                        ForEach(appState.currentMessages) { message in
                            ChatBubble(message: message)
                        }
                        if appState.isChatting || appState.isExecutingTask {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .controlSize(.small)
                                        .tint(Color.afmBlue)
                                    Text(appState.isExecutingTask ? "Running selected tool..." : "Thinking...")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(10)
                                .background(Color.afmCard, in: RoundedRectangle(cornerRadius: 8))
                                if appState.isExecutingTask {
                                    ToolActivityStepsView()
                                }
                            }
                            .frame(maxWidth: 520, alignment: .leading)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: appState.currentMessages.count) {
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                .onChange(of: appState.isChatting || appState.isExecutingTask) {
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
            Divider()
            composer
                .padding(14)
        }
        .onChange(of: appState.activeChat?.id) {
            recallIndex = nil
            recalledDraft = ""
            draft = ""
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField(appState.mode == .generalChat ? "Message Local AI..." : "Ask checked files...", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .lineLimit(3...12)
                .padding(12)
                .frame(minHeight: 92, alignment: .topLeading)
                .background(Color.afmCard, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.afmBorder)
                }
                .onSubmit(send)
                .onKeyPress { press in
                    guard press.key == .return else { return .ignored }
                    if press.modifiers.contains(.shift) {
                        draft.append("\n")
                        return .handled
                    }
                    return .ignored
                }
                .onKeyPress(.upArrow) {
                    recall(.up)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    recall(.down)
                    return .handled
                }
            Button {
                send()
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(ActionGradient(), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(appState.isChatting || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (appState.mode == .workspace && appState.selectedFilePaths.isEmpty))
            .help("Send")
        }
    }

    private func send() {
        let text = draft
        draft = ""
        appState.sendChat(text)
    }
}

struct ActionGradient: ShapeStyle {
    func resolve(in environment: EnvironmentValues) -> some ShapeStyle {
        LinearGradient(colors: [Color.afmBlue, Color(red: 0.06, green: 0.55, blue: 0.95)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

private struct ChatEmptyView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.afmBlueLight)
                    .frame(width: 72, height: 72)
                Image(systemName: appState.mode == .generalChat ? "bubble.left.and.bubble.right" : "text.page.badge.magnifyingglass")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.afmBlue)
            }
            Text(appState.mode == .generalChat ? "General Chat" : "Chat with checked files")
                .font(.system(size: 20, weight: .bold))
            Text(appState.mode == .generalChat
                 ? "Ask anything — nothing in this chat is grounded in a folder."
                 : "Only checked files in the left panel are available for retrieval and tools.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct ChatBubble: View {
    @EnvironmentObject private var appState: AppState
    var message: ChatMessage
    @State private var isCopied = false
    @State private var isSaved = false

    private var isUser: Bool { message.role == .user }

    private var showsBubbleBox: Bool { isUser || !message.isFailed }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if isUser { Spacer(minLength: 80) }
            if !isUser {
                ZStack {
                    Circle()
                        .fill(Color.afmBlue)
                        .frame(width: 26, height: 26)
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .padding(.top, 2)
            }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                contentBox
                actions
            }
            .frame(maxWidth: isUser ? 520 : .infinity, alignment: isUser ? .trailing : .leading)
        }
    }

    private var contentBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !isUser {
                MarkdownText(markdown: message.markdown)
                    .textSelection(.enabled)
            } else {
                Text(message.markdown)
                    .textSelection(.enabled)
                    .foregroundStyle(.white)
            }
            if !message.citations.isEmpty {
                Text("\(message.citations.count) citations")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            if let plan = message.filePlan {
                PlanReviewCard(messageID: message.id, plan: plan, outcome: message.planApproved)
            }
        }
        .padding(showsBubbleBox ? 14 : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if showsBubbleBox {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isUser ? AnyShapeStyle(ActionGradient()) : AnyShapeStyle(Color.afmCard))
            }
        }
        .overlay {
            if showsBubbleBox && !isUser {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.afmBorder)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 4) {
            Spacer()
            Button {
                copy(message.markdown)
                flash($isCopied)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 9))
                        .foregroundStyle(isCopied ? .green : .secondary)
                    Text(isCopied ? "Copied" : "Copy")
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(isUser ? "Copy message" : "Copy as Markdown")
            if !isUser && appState.mode == .workspace && !message.isFailed {
                Button {
                    if appState.saveChatMessage(message) {
                        flash($isSaved)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isSaved ? "checkmark" : "externaldrive.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(isSaved ? .green : .secondary)
                        Text(isSaved ? "Saved" : "Save")
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Save response")
            }
        }
        .padding(.horizontal, 4)
    }

    private func copy(_ markdown: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
    }

    private func flash(_ isOn: Binding<Bool>) {
        withAnimation(.easeOut(duration: 0.12)) { isOn.wrappedValue = true }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.easeIn(duration: 0.12)) { isOn.wrappedValue = false }
        }
    }
}

struct ToolPlanView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if appState.activeTemplate == nil {
                Text("Choose a tool to preview its plan and activity.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ActiveTaskSummaryView(task: appState.activeTask)
            }
        }
    }
}

private struct ActiveTaskSummaryView: View {
    @EnvironmentObject private var appState: AppState
    var task: StudioTask

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                StatusBadge(title: task.status.rawValue, systemImage: task.status.symbol, tint: task.status.tint, spinner: task.status == .running)
                Spacer()
                Button {
                    appState.runActiveTask()
                } label: {
                    if appState.isExecutingTask {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini)
                            Text("Run")
                        }
                    } else {
                        Label("Run", systemImage: "play.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!appState.canRunActiveTask)
            }

            LabeledBlock(title: "Plan", symbol: "list.bullet.clipboard") {
                ForEach(Array(task.plan.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1).")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        Text(step)
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            LabeledBlock(title: "Activity", symbol: "waveform.path.ecg") {
                ForEach(task.activity) { event in
                    ActivityRow(event: event)
                }
            }
        }
    }
}

struct LabeledBlock<Content: View>: View {
    var title: String
    var symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.headline)
            content
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct MarkdownText: View {
    let markdown: String
    private let parsedBlocks: [MarkdownBlock]

    init(markdown: String) {
        self.markdown = markdown
        self.parsedBlocks = MarkdownBlockParser.parse(markdown)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(parsedBlocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        Group {
            switch block {
            case .heading(let level, let text):
                Text(inline(text))
                    .font(headingFont(for: level))
            case .paragraph(let text):
                Text(inline(text))
            case .unordered(let items):
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .top, spacing: 6) {
                            Text("•")
                                .foregroundStyle(.secondary)
                            Text(inline(item))
                        }
                    }
                }
            case .ordered(let items):
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(items.enumerated()), id: \.offset) { offset, item in
                        HStack(alignment: .top, spacing: 6) {
                            Text("\(offset + 1).")
                                .foregroundStyle(.secondary)
                            Text(inline(item))
                        }
                    }
                }
            case .quote(let text):
                Text(inline(text))
                    .italic()
                    .foregroundStyle(.secondary)
                    .padding(.leading, 8)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.35))
                            .frame(width: 3)
                    }
            case .callout(let kind, let text):
                let accent = Self.calloutAccent(for: kind)
                VStack(alignment: .leading, spacing: 6) {
                    Label(kind.capitalized, systemImage: Self.calloutIcon(for: kind))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accent)
                    if !text.isEmpty {
                        Text(inline(text))
                            .font(.caption)
                            .foregroundStyle(.primary)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Self.calloutFill(for: kind), in: RoundedRectangle(cornerRadius: 8))
            case .code(let text):
                Text(text)
                    .font(.system(.caption, design: .monospaced))
                    .lineSpacing(2)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
            case .footnote(let label, let content):
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("[\(label)]")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(inline(content))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            case .divider:
                Divider()
            case .table(let header, let rows):
                tableGrid(header: header, rows: rows)
            }
        }
        .textSelection(.enabled)
    }

    private func tableGrid(header: [String], rows: [[String]]) -> some View {
        let maxColumns = max(header.count, rows.map(\.count).max() ?? 0)
        guard maxColumns > 0 else {
            return AnyView(EmptyView())
        }
        let allRows = [header] + rows
        let columnWidths = (0..<maxColumns).map { col -> CGFloat in
            let longest = allRows.compactMap { row -> String? in
                col < row.count && !row[col].isEmpty ? row[col] : nil
            }.map(\.count).max() ?? 0
            let target = CGFloat(longest) * 6.8 + 16
            return min(max(target, 56), 240)
        }
        return AnyView(
            ScrollView(.horizontal) {
                VStack(spacing: 0) {
                    ForEach(Array(allRows.enumerated()), id: \.offset) { rowOffset, row in
                        HStack(alignment: .top, spacing: 0) {
                            ForEach(0..<maxColumns, id: \.self) { col in
                                let content = col < row.count ? row[col] : ""
                                let isHeader = rowOffset == 0
                                Text(inline(content))
                                    .font(.system(.caption))
                                    .foregroundStyle(Color.primary)
                                    .fontWeight(isHeader ? .semibold : .regular)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .frame(width: columnWidths[col], alignment: .leading)
                            }
                        }
                        .background(
                            rowOffset == 0
                                ? Color.primary.opacity(0.05)
                                : (rowOffset.isMultiple(of: 2) ? Color.primary.opacity(0.02) : Color.clear)
                        )
                    }
                }
                .overlay {
                    Rectangle()
                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        )
    }

    private func inline(_ text: String) -> AttributedString {
        var out = AttributedString("")
        let nsText = text as NSString
        var cursor = text.startIndex
        if let regex = Self.footnoteRefRegex {
            for match in regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length)) {
                guard let range = Range(match.range, in: text) else { continue }
                if range.lowerBound > cursor {
                    out.append(Self.rawInline(String(text[cursor..<range.lowerBound])))
                }
                var reference = AttributedString(String(text[range]))
                reference.baselineOffset = 5
                reference.font = .system(.caption, design: .rounded)
                reference.foregroundColor = .secondary
                out.append(reference)
                cursor = range.upperBound
            }
        }
        if cursor < text.endIndex {
            out.append(Self.rawInline(String(text[cursor...])))
        }
        return out
    }

    private static let footnoteRefRegex = (try? NSRegularExpression(pattern: "\\[\\^[^]]+\\]"))

    private static func calloutAccent(for kind: String) -> Color {
        switch kind {
        case "ERROR": .red
        case "WARNING": .orange
        case "NOTE": .blue
        case "SUCCESS": .green
        default: .secondary
        }
    }

    private static func calloutFill(for kind: String) -> Color {
        switch kind {
        case "ERROR": .red.opacity(0.12)
        case "WARNING": .orange.opacity(0.16)
        case "NOTE": .blue.opacity(0.10)
        case "SUCCESS": .green.opacity(0.10)
        default: Color.primary.opacity(0.05)
        }
    }

    private static func calloutIcon(for kind: String) -> String {
        switch kind {
        case "ERROR": "nosign"
        case "WARNING": "exclamationmark.triangle.fill"
        case "NOTE": "info.circle.fill"
        case "SUCCESS": "checkmark.circle.fill"
        default: "info.circle"
        }
    }

    private static func rawInline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }

    private func headingFont(for level: Int) -> Font {
        switch level {
        case 1: .title.bold()
        case 2: .title2.bold()
        case 3: .title3.bold()
        default: .headline
        }
    }
}

private struct PlanReviewCard: View {
    @EnvironmentObject private var appState: AppState
    var messageID: UUID
    var plan: FileOperationPlan
    var outcome: Bool?
    @State private var destinations: [String: String] = [:]
    @State private var initialized = false

    private var sortedOps: [RenamePlanRecord] {
        plan.operations.sorted { $0.currentPath < $1.currentPath }
    }

    private var workspaceURL: URL {
        appState.workspace?.url ?? URL(fileURLWithPath: "/")
    }

    private var invalidRows: [String] {
        sortedOps.filter { isRowInvalid($0.currentPath) }.map(\.currentPath)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let outcome {
                Label(outcome ? "Plan approved. See the activity log for move results." : "Plan rejected. No files were changed.",
                      systemImage: outcome ? "checkmark.seal.fill" : "xmark.seal.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(outcome ? Color.green : Color.secondary)
            } else {
                Label("Proposed moves (\(sortedOps.count))", systemImage: "doc.badge.gearshape")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                VStack(spacing: 6) {
                    ForEach(sortedOps, id: \.currentPath) { op in
                        HStack(spacing: 6) {
                            Text(op.currentPath)
                                .font(.caption)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "arrow.right")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            TextField("Folder", text: destinationBinding(for: op.currentPath))
                                .textFieldStyle(.roundedBorder)
                                .font(.caption)
                                .frame(minWidth: 140)
                            if isRowInvalid(op.currentPath) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.red)
                                    .help("Invalid destination")
                            }
                        }
                    }
                }
                Text("You can edit each destination folder before approving. Files are moved within the workspace only; nothing is deleted or overwritten.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if !appState.permissions.write {
                    Label("Write permission is off — enable Write files to approve.", systemImage: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                HStack(spacing: 8) {
                    Button {
                        var finalDest: [String: String] = [:]
                        for op in sortedOps {
                            let dest = (destinations[op.currentPath] ?? op.proposedPath).trimmingCharacters(in: .whitespacesAndNewlines)
                            if !dest.isEmpty { finalDest[op.currentPath] = dest }
                        }
                        appState.approvePlan(messageID: messageID, destinations: finalDest)
                    } label: {
                        Label("Approve", systemImage: "checkmark")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(!appState.permissions.write || !invalidRows.isEmpty || outcome != nil)
                    Button(role: .destructive) {
                        appState.rejectPlan(messageID: messageID)
                    } label: {
                        Label("Reject", systemImage: "xmark")
                    }
                    .buttonStyle(.bordered)
                    .disabled(outcome != nil)
                    Spacer()
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.08))
        }
        .onAppear {
            if !initialized {
                for op in plan.operations {
                    destinations[op.currentPath] = op.proposedPath
                }
                initialized = true
            }
        }
    }

    private func isRowInvalid(_ from: String) -> Bool {
        let dest = (destinations[from] ?? proposedPath(for: from)).trimmingCharacters(in: .whitespacesAndNewlines)
        return dest.isEmpty || PlanOperationParser.resolveDestination(dest, in: workspaceURL) == nil
    }

    private func proposedPath(for from: String) -> String {
        plan.operations.first(where: { $0.currentPath == from })?.proposedPath ?? ""
    }

    private func destinationBinding(for from: String) -> Binding<String> {
        Binding(
            get: { destinations[from] ?? proposedPath(for: from) },
            set: { destinations[from] = $0 }
        )
    }
}

private struct ToolActivityStepsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var expanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 6) {
                if appState.activeTask.activity.isEmpty {
                    Text("Preparing steps...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(appState.activeTask.activity) { event in
                        ActivityRow(event: event)
                    }
                }
            }
            .padding(.top, 4)
        } label: {
            Label("Tool steps", systemImage: "list.bullet.rectangle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct ActivityRow: View {
    var event: ActivityEvent

    var body: some View {
        if event.state != .pending {
            HStack(alignment: .top, spacing: 8) {
                if event.state == .running {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 18)
                } else {
                    Image(systemName: event.state.symbol)
                        .foregroundStyle(event.state.tint)
                        .frame(width: 18)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .font(.caption.weight(.semibold))
                    Text(event.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
