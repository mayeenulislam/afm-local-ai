import SwiftUI

struct InspectorView: View {
    @EnvironmentObject private var appState: AppState
    @State private var presentedResponse: SavedResponse?
    @State private var toolDetailTemplate: TaskTemplate?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                workbenchPanel
                savedResponsesPanel
            }
            .padding(14)
        }
        .background(Color.afmWindow)
        .sheet(item: $presentedResponse) { response in
            SavedResponseDetailView(response: response) {
                appState.deleteSavedResponse(response)
                presentedResponse = nil
            }
        }
        .sheet(item: $toolDetailTemplate) { template in
            ToolInfoView(template: template,
                         onClose: { toolDetailTemplate = nil },
                         onRun: {
                             toolDetailTemplate = nil
                             appState.runTool(template)
                         })
                .environmentObject(appState)
                .padding(18)
                .frame(width: 380)
        }
    }

    private var savedResponsesPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            AFMSectionLabel(text: "Saved Responses")
            if appState.currentSavedResponses.isEmpty {
                Label("Nothing saved here yet", systemImage: "tray")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.afmCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.afmBorder)
                    }
            } else {
                VStack(spacing: 4) {
                    ForEach(appState.currentSavedResponses) { response in
                        SavedResponseRow(response: response) {
                            presentedResponse = response
                        } onDelete: {
                            appState.deleteSavedResponse(response)
                        }
                    }
                }
                .padding(6)
                .background(Color.afmCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.afmBorder)
                }
            }
        }
    }

    private var workbenchPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                AFMSectionLabel(text: "Workspace Tools")
                Spacer()
                Text("\(appState.taskTemplates.count)")
                    .font(.afmMono(10))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.afmSurface, in: Capsule())
            }
            toolsContent
        }
    }

    private var toolsContent: some View {
        LazyVStack(spacing: 8) {
            ForEach(appState.taskTemplates) { template in
                ToolCard(template: template) {
                    toolDetailTemplate = template
                }
            }
        }
    }

    static func permissionNames(_ permissions: RequiredPermissions) -> [String] {
        var names: [String] = []
        if permissions.contains(.write) { names.append("Write files") }
        if permissions.contains(.delete) { names.append("Delete files") }
        if permissions.contains(.shell) { names.append("Shell commands") }
        if permissions.contains(.network) { names.append("Network") }
        return names.isEmpty ? ["Read"] : names
    }

}

private struct ToolCard: View {
    @EnvironmentObject private var appState: AppState
    var template: TaskTemplate
    var onOpen: () -> Void
    @State private var isGlowing = false

    private var isRunning: Bool { appState.isExecutingTask && appState.activeTemplate?.id == template.id }
    private var isBusy: Bool { appState.isExecutingTask }

    var body: some View {
        Button {
            if !isBusy {
                onOpen()
            }
        } label: {
            cardLabel
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .help("Open tool details")
        .accessibilityLabel("\(template.title). \(template.subtitle)")
    }

    private var cardLabel: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.afmBlueLight)
                    .frame(width: 34, height: 34)
                if isRunning {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: template.symbol)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.afmBlue)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(template.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(template.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            if isRunning {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.blue, .teal, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
                    .shadow(color: .blue.opacity(0.6), radius: isGlowing ? 6 : 2)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isGlowing)
                    .onAppear { isGlowing = true }
                    .onDisappear { isGlowing = false }
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct ToolInfoView: View {
    @EnvironmentObject private var appState: AppState
    var template: TaskTemplate
    var onClose: () -> Void
    var onRun: () -> Void

    private var isActive: Bool { appState.activeTemplate?.id == template.id }
    private var isBusy: Bool { appState.isExecutingTask }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: template.symbol)
                    .foregroundStyle(Color.afmBlue)
                Text(template.title)
                    .font(.headline)
                Spacer()
                if isActive {
                    StatusBadge(title: appState.activeTask.status.rawValue, systemImage: appState.activeTask.status.symbol, tint: appState.activeTask.status.tint)
                }
            }

            Text(template.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !template.required.isEmpty {
                Label("Needs: \(InspectorView.permissionNames(template.required).joined(separator: ", "))",
                      systemImage: "checkmark.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            LabeledBlock(title: "Plan", symbol: "list.bullet.clipboard") {
                ForEach(Array(appState.planSteps(for: template).enumerated()), id: \.offset) { index, step in
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

            Divider()

            HStack(spacing: 8) {
                Spacer()
                Button("Close", action: onClose)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button(action: onRun) {
                    Label(isActive && isBusy ? "Running" : "Run",
                          systemImage: isActive && isBusy ? "arrow.triangle.2.circlepath" : "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.afmBlue)
                .controlSize(.small)
                .disabled(isBusy)
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}

struct RAGInfoView: View {
    var appState: AppState
    var showWorkspaceName = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let file = appState.selectedFile {
                Label(file.name, systemImage: file.kind.symbol)
                    .foregroundStyle(file.kind.tint)
                Text(file.relativePath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
                PermissionRow(title: "Type", state: file.kind.rawValue, tint: file.kind.tint)
                PermissionRow(title: "Size", state: ByteCountFormatter.string(fromByteCount: file.byteCount, countStyle: .file), tint: .secondary)
            } else if let workspace = appState.workspace {
                if showWorkspaceName {
                    Label(appState.workspaceDisplayName, systemImage: workspace.kind.symbol)
                        .foregroundStyle(.blue)
                    Text(workspace.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .textSelection(.enabled)
                }
                StatGrid(workspace: workspace)
                fileTypesNote
            } else {
                Label(appState.mode == .generalChat ? "General chat" : "Dashboard", systemImage: appState.mode == .generalChat ? "bubble.left.and.bubble.right" : "rectangle.grid.2x2")
                    .foregroundStyle(.secondary)
                Text("Open a folder for RAG, or use general chat without workspace retrieval.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
private var fileTypesNote: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("Files that are eligible for workspace context", systemImage: "doc.badge.ellipsis")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            SupportedFileTypesTable()
        }
        .frame(minWidth: 300, maxWidth: 380, alignment: .leading)
        .padding(.top, 2)
    }
}

struct SupportedFileTypesTable: View {
    private let rows = FileKindSuffixes.supportedTable

    var body: some View {
        VStack(spacing: 0) {
            headerRow
            Divider().overlay(Color.afmBorder)
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                rowView(title: row.title, extensions: row.extensions)
                    .background(index.isMultiple(of: 2) ? Color.afmSurface : Color.afmCard)
                if index != rows.count - 1 {
                    Divider().overlay(Color.afmBorder)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.afmBorder)
        }
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            Text("Type")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 86, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            Divider().overlay(Color.afmBorder)
            Text("Extensions")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
        }
        .frame(maxWidth: .infinity)
        .background(Color.afmBlueLight.opacity(0.4))
    }

    private func rowView(title: String, extensions: [String]) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 86, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
            Divider().overlay(Color.afmBorder)
            Text(extensions.map { ".\($0)" }.joined(separator: " "))
                .font(.afmMono(10))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
        }
        .frame(maxWidth: .infinity)
    }
}

struct ContextBudgetMeter: View {
    var budget: ContextBudget
    var checkedEstimate: Int

    private var fixed: Int { budget.instructions + budget.expectedResponse + budget.promptOverhead }
    private var contentBudget: Int { budget.contentBudget }

    static func state(checkedEstimate: Int, limit: Int) -> BudgetState {
        if checkedEstimate == 0 { return .idle }
        return checkedEstimate > limit ? .selects : .fits
    }

    private var state: BudgetState {
        Self.state(checkedEstimate: checkedEstimate, limit: budget.limit)
    }

    private var content: Int { min(checkedEstimate, budget.limit) }

    private var tint: Color {
        switch state {
        case .idle: .secondary
        case .fits: .green
        case .selects: .orange
        }
    }

    private var symbol: String {
        switch state {
        case .idle: "doc.questionmark"
        case .fits: "checkmark.circle"
        case .selects: "arrow.triangle.2.circlepath"
        }
    }

    private var caption: String {
        switch state {
        case .idle: "No files checked. Chat and tools run without file context."
        case .fits: "Good to go — all \(checkedEstimate.formatted()) checked tokens fit inside the model's ~\(budget.limit.formatted())-token window."
        case .selects: "Exceeds — your checked files (~\(checkedEstimate.formatted()) tokens) exceed the model's ~\(budget.limit.formatted())-token window. To fit, the app sends only the most relevant ~\(contentBudget.formatted()) per run, skipping the rest."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("Context window")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("~\(checkedEstimate.formatted()) / \(budget.limit.formatted())")
                    .font(.caption2)
                    .foregroundStyle(state == .fits ? .secondary : tint)
                    .monospacedDigit()
            }
            ProgressView(value: Double(content), total: Double(budget.limit))
                .tint(tint)
            Text("Reserved for instructions, formatting & reply: \(fixed.formatted())")
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 4) {
                Image(systemName: symbol)
                    .font(.caption2)
                    .foregroundStyle(tint)
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(tint)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    enum BudgetState: Equatable {
        case idle, fits, selects
    }
}

struct SavedResponseRow: View {
    var response: SavedResponse
    var onOpen: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.afmBlueLight)
                    .frame(width: 28, height: 28)
                Image(systemName: response.kind == .chat ? "bubble.left.fill" : "hammer.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.afmBlue)
            }
            Button(action: onOpen) {
                Text(response.title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
            .help("Delete saved response")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }
}

struct SavedResponseDetailView: View {
    var response: SavedResponse
    var onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @State private var title = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: response.kind == .chat ? "bubble.left" : "hammer")
                    .font(.title3.weight(.semibold))
                TextField("Title", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)
                    .onChange(of: title) { _, newValue in
                        appState.renameSavedResponse(response, title: newValue)
                    }
                Spacer()
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }

            ScrollView {
                MarkdownText(markdown: response.markdown)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(20)
        .frame(minWidth: 680, minHeight: 520)
        .onAppear { title = response.title }
    }
}

private struct StatGrid: View {
    var workspace: Workspace

    var body: some View {
        VStack(spacing: 7) {
            stat("Markdown", workspace.summary.count(for: .markdown))
            stat("Code", workspace.summary.count(for: .code))
            stat("PDF", workspace.summary.count(for: .pdf))
            stat("Docs", workspace.summary.count(for: .document) + workspace.summary.count(for: .presentation))
            stat("Data", workspace.summary.count(for: .data))
        }
        .frame(maxWidth: .infinity)
    }

    private func stat(_ title: String, _ value: Int) -> some View {
        HStack {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text("\(value)").font(.caption.weight(.semibold))
        }
    }
}

struct PermissionRow: View {
    var title: String
    var state: String
    var tint: Color

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(state)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
        }
    }
}

struct PermissionToggle: View {
    var title: String
    var systemImage: String
    var isOn: Binding<Bool>

    var body: some View {
        Toggle(isOn: isOn) {
            Label(title, systemImage: systemImage)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }
}

private struct StatusLine: View {
    var title: String
    var detail: String
    var systemImage: String
    var tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
