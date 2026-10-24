import SwiftUI

// MARK: - Global Manager Sheet

struct MCPServerManagerSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var editingServer: MCPServerConfig?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.afmBlueLight)
                        .frame(width: 40, height: 40)
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.afmBlue)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("MCP Servers")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Global server registry")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    editingServer = MCPServerConfig(name: "")
                } label: {
                    Label("Add Server", systemImage: "plus")
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.afmBlue)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.afmBlueLight, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .disabled(editingServer != nil)
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .background(Color.afmCard, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(Color.afmBorder)
                        }
                }
                .buttonStyle(.plain)
            }

            if appState.mcpServers.isEmpty {
                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color.afmBlueLight)
                            .frame(width: 56, height: 56)
                        Image(systemName: "point.3.connected.trianglepath.dotted")
                            .font(.system(size: 22))
                            .foregroundStyle(Color.afmBlue)
                    }
                    Text("No MCP servers configured")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Add a stdio or Streamable HTTP server to expose its tools to a workspace. Transport is configured here; connection and tool discovery are planned next.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)
                }
                .frame(maxWidth: .infinity, minHeight: 160)
                .background(Color.afmSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.afmBorder, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                }
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(appState.mcpServers) { server in
                            MCPServerRow(server: server) {
                                editingServer = server
                            }
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(width: 480, height: 380)
        .sheet(item: $editingServer) { server in
            MCPServerEditor(server: server)
                .environmentObject(appState)
        }
    }
}

// MARK: - Server Row

struct MCPServerRow: View {
    let server: MCPServerConfig
    let onEdit: () -> Void
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill((server.transport.isRemote ? Color.orange : Color.green).opacity(0.14))
                    .frame(width: 32, height: 32)
                Image(systemName: server.transport.symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(server.transport.isRemote ? Color.orange : Color.green)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(server.name)
                        .font(.system(size: 12, weight: .semibold))
                    MCPTrustBadge(isRemote: server.transport.isRemote)
                }
                Text(server.detailLine)
                    .font(.afmMono(10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                onEdit()
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Edit server")
            Button {
                appState.deleteMCPServer(server.id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
            .help("Delete server")
        }
        .padding(10)
        .background(Color.afmCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.afmBorder)
        }
    }
}

// MARK: - Trust Badge

struct MCPTrustBadge: View {
    var isRemote: Bool

    var body: some View {
        Text(isRemote ? "Remote" : "Local")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(isRemote ? Color.orange : Color.green)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background((isRemote ? Color.orange : Color.green).opacity(0.12), in: Capsule())
    }
}

// MARK: - Server Editor

struct MCPServerEditor: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var model: MCPServerConfig
    @State private var headers: [HeaderField]

    init(server: MCPServerConfig) {
        _model = State(initialValue: server)
        _headers = State(initialValue: server.headers.map { HeaderField(key: $0.key, value: $0.value) })
    }

    private struct HeaderField: Identifiable {
        let id = UUID()
        var key: String
        var value: String
    }

    private var isNew: Bool {
        !appState.mcpServers.contains(where: { $0.id == model.id })
    }

    private var canSave: Bool {
        let trimmedName = model.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return false }
        switch model.transport {
        case .stdio:
            return !model.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .streamableHTTP:
            let url = model.url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return url.hasPrefix("https://") || url.hasPrefix("http://")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.afmBlueLight)
                        .frame(width: 28, height: 28)
                    Image(systemName: isNew ? "plus" : "pencil")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.afmBlue)
                }
                Text(isNew ? "Add MCP Server" : "Edit MCP Server")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .background(Color.afmCard, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(Color.afmBorder)
                        }
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Name")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                AFMTextField(title: "e.g. Filesystem", text: $model.name)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Transport")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Picker("", selection: $model.transport) {
                    ForEach(MCPTransportType.allCases) { transport in
                        Text(transport.rawValue).tag(transport)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            if model.transport == .stdio {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Command")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    AFMTextField(title: "e.g. /usr/local/bin/npx", text: $model.command)
                    Text("Arguments")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    AFMTextField(title: "e.g. -y @modelcontextprotocol/server-filesystem /path", text: $model.arguments)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("URL")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    AFMTextField(title: "https://example.com/mcp", text: $model.url, mono: true)
                    Text("Headers (optional)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    ForEach($headers) { $field in
                        HStack(spacing: 6) {
                            AFMTextField(title: "Header", text: $field.key, mono: true, padding: 8, cornerRadius: 7)
                                .frame(width: 140)
                            AFMTextField(title: "Value", text: $field.value, mono: true, padding: 8, cornerRadius: 7)
                            Button {
                                headers.removeAll { $0.id == field.id }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(.system(size: 12))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                    }
                    Button {
                        headers.append(HeaderField(key: "", value: ""))
                    } label: {
                        Label("Add header", systemImage: "plus")
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.afmBlue)
                }

                Label("Remote server: workspace context may leave this Mac. Header values are stored in plaintext in Application Support.", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Color.orange.opacity(0.2))
                    }
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.afmSurface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.afmBorder)
                }
                Button(isNew ? "Add" : "Save") {
                    save()
                    dismiss()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(ActionGradient(), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .disabled(!canSave)
            }
        }
        .padding(18)
        .frame(width: 400)
        .background(Color.afmWindow)
    }

    private func save() {
        var cleaned = model
        cleaned.name = model.name.trimmingCharacters(in: .whitespacesAndNewlines)
        var newHeaders: [String: String] = [:]
        for field in headers {
            let key = field.key.trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty {
                newHeaders[key] = field.value
            }
        }
        cleaned.headers = newHeaders
        if isNew {
            appState.addMCPServer(cleaned)
        } else {
            appState.updateMCPServer(cleaned)
        }
    }
}
