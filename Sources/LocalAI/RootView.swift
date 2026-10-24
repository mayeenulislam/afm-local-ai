import SwiftUI

final class ColumnWidths: ObservableObject {
    @Published var sidebar: CGFloat = 290
    @Published var inspector: CGFloat = 320
}

private enum AppAppearance: String, CaseIterable {
    case system, light, dark

    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    var name: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var next: AppAppearance {
        switch self {
        case .system: .light
        case .light: .dark
        case .dark: .system
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("appAppearance") private var appearanceRaw = AppAppearance.system.rawValue
    @StateObject private var columnWidths = ColumnWidths()
    @State private var showingMCPServers = false
    @State private var showModelDiagnostics = false
    @State private var editableTitle = ""

    private var appearance: AppAppearance {
        AppAppearance(rawValue: appearanceRaw) ?? .system
    }

    var body: some View {
        VStack(spacing: 0) {
            if appState.mode != .dashboard {
                headerRow
            }
            modeContent
            footer
        }
        .background(Color.afmWindow)
        .overlay(alignment: .topTrailing) {
            if appState.mode == .dashboard {
                floatingIsland
                    .padding(16)
            }
        }
        .onAppear {
            editableTitle = appState.activeChat?.title ?? ""
        }
        .onChange(of: appState.activeChat?.id) {
            editableTitle = appState.activeChat?.title ?? ""
        }
        .onChange(of: appState.activeChat?.title) {
            editableTitle = appState.activeChat?.title ?? ""
        }
        .sheet(isPresented: $showingMCPServers) {
            MCPServerManagerSheet()
                .environmentObject(appState)
        }
        .sheet(isPresented: $showModelDiagnostics) {
            ModelDiagnosticsView()
                .environmentObject(appState)
        }
    }

    @ViewBuilder
    private var modeContent: some View {
        Group {
            if appState.mode == .workspace {
                threeColumn
            } else if appState.mode == .generalChat {
                twoColumn
            } else {
                TaskCanvasView()
            }
        }
        .preferredColorScheme(appearance.colorScheme)
    }

    private var twoColumn: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 290, max: 420)
                .background(widthReader { columnWidths.sidebar = $0 })
        } detail: {
            TaskCanvasView()
                .navigationSplitViewColumnWidth(min: 420, ideal: 680)
        }
    }

    private var threeColumn: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 290, max: 420)
                .background(widthReader { columnWidths.sidebar = $0 })
        } content: {
            TaskCanvasView()
                .navigationSplitViewColumnWidth(min: 420, ideal: 680)
        } detail: {
            InspectorView()
                .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 420)
                .background(widthReader { columnWidths.inspector = $0 })
        }
    }

    private func widthReader(_ assign: @escaping (CGFloat) -> Void) -> some View {
        GeometryReader { geo in
            Color.clear
                .onAppear {
                    assign(geo.size.width)
                }
                .onChange(of: geo.size.width) { _, newValue in
                    assign(newValue)
                }
        }
        .allowsHitTesting(false)
    }

    // MARK: Header Row

    private var headerRow: some View {
        HStack(spacing: 0) {
            backButton
                .frame(width: headerLeftWidth, alignment: .leading)
                .padding(.horizontal, 16)

            headerCenterContent
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            headerRightContent
                .frame(width: headerRightWidth, alignment: .trailing)
                .padding(.horizontal, 16)
        }
        .frame(height: 46)
        .background(Color.afmSidebar)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var floatingIsland: some View {
        HStack(spacing: 6) {
            appearanceButton
            headerStatusBadge
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.afmSidebar, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(Color.afmBorder)
        }
        .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
    }

    private var headerLeftWidth: CGFloat {
        columnWidths.sidebar
    }

    private var headerRightWidth: CGFloat? {
        appState.mode == .workspace ? columnWidths.inspector : nil
    }

    private var backButton: some View {
        Button {
            appState.showDashboard()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .semibold))
                Text("Back to Dashboard")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(.primary.opacity(0.8))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.afmSurface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.afmBorder)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var headerCenterContent: some View {
        switch appState.mode {
        case .generalChat:
            chatTitleCluster
                .padding(.horizontal, 16)
        case .workspace:
            workspaceTitleCluster
                .padding(.horizontal, 16)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var chatTitleCluster: some View {
        if appState.activeChat == nil {
            HStack(spacing: 6) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.afmBlue)
                Text("New General Chat")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        } else {
            HStack(spacing: 6) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.afmBlue)
                TextField("Chat title", text: $editableTitle, onCommit: {
                    appState.renameActiveChat(editableTitle)
                })
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .multilineTextAlignment(.leading)
                .frame(width: 300)
            }
        }
    }

    private var workspaceTitleCluster: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.afmBlue)
                .frame(width: 6, height: 6)
            Text("RAG Workspace:")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text(appState.workspaceDisplayName)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
        }
    }

    private var appearanceButton: some View {
        Button {
            appearanceRaw = appearance.next.rawValue
        } label: {
            Image(systemName: appearance.symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Appearance: \(appearance.name). Click to switch.")
    }

    private var headerRightContent: some View {
        HStack(spacing: 6) {
            if appState.mode == .generalChat {
                headerPillButton(title: "Clear Chat", symbol: "arrow.clockwise") {
                    appState.clearSession()
                }
                headerPillButton(title: "Delete", symbol: "trash", tint: .red) {
                    appState.deleteActiveChat()
                }
                .disabled(appState.activeChat == nil)
            } else if appState.mode == .workspace {
                headerPillButton(title: "Clear Chat", symbol: "arrow.clockwise") {
                    appState.clearSession()
                }
            }

            Divider()
                .frame(height: 18)
                .padding(.horizontal, 2)

            if appState.mode == .dashboard && appState.mcpTransportReady {
                AFMIconButton(symbol: "point.3.connected.trianglepath.dotted", help: "Manage MCP servers") {
                    showingMCPServers = true
                }
            }
            appearanceButton

            headerStatusBadge
        }
    }

    private func headerPillButton(title: String, symbol: String, tint: Color = .primary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(tint.opacity(0.85))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color.afmSurface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.afmBorder)
                }
        }
        .buttonStyle(.plain)
    }

    private var headerStatusBadge: some View {
        let hasActiveRemoteMCP = appState.mcpTransportReady && appState.currentWorkspaceMCPSettings.enabledServerIDs.contains { id in
            appState.mcpServers.first(where: { $0.id == id })?.transport.isRemote == true
        }
        let status = hasActiveRemoteMCP ? (title: "Remote MCP", dot: Color.orange)
            : appState.modelStatus.isOnDeviceProvider ? (title: "On Device", dot: Color.green)
            : (title: "Mock Mode", dot: Color.orange)
        return Button {
            showModelDiagnostics = true
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(status.dot)
                    .frame(width: 6, height: 6)
                Text(status.title)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(status.dot)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(status.dot.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .help("Show model diagnostics")
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                Text("Developed by")
                Link("Mayeenul Islam", destination: URL(string: "https://mayeenulislam.github.io")!)
                    .foregroundStyle(Color.accentColor)
            }
            Text("•")
                .foregroundStyle(.tertiary)
            Text("Apple Foundation Models (AFM) Native")
            Spacer()
            if appState.modelStatus.isOnDeviceProvider {
                Text("Typical ANE latency: ~28ms/token")
                    .font(.afmMono(11))
                    .foregroundStyle(.secondary)
            } else {
                Text("Mock Mode • no on-device model")
                    .font(.afmMono(11))
                    .foregroundStyle(.secondary)
            }
            StatusDotBadge(
                text: appState.modelStatus.isOnDeviceProvider ? "Ready" : "Not Ready",
                dotColor: appState.modelStatus.isOnDeviceProvider ? .green : .orange
            )
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .frame(height: 28)
        .background(Color.afmSidebar)
        .overlay(alignment: .top) {
            Divider()
        }
    }
}

struct StatusBadge: View {
    var title: String
    var systemImage: String
    var tint: Color
    var spinner = false

    var body: some View {
        Group {
            if spinner {
                HStack(spacing: 5) {
                    ProgressView().controlSize(.mini)
                    Text(title)
                }
            } else {
                Label(title, systemImage: systemImage)
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(tint.opacity(0.12), in: Capsule())
    }
}