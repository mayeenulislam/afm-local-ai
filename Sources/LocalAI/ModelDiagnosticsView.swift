import SwiftUI

@MainActor
struct ModelDiagnosticsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    statusHero
                    AFMSectionLabel(text: "Model Specs")
                    specGrid
                    AFMSectionLabel(text: "Supported File Types")
                    fileTypesCard
                    if !appState.modelStatus.supportedLanguages.isEmpty {
                        HStack(spacing: 8) {
                            AFMSectionLabel(text: "Supported Languages")
                            Spacer()
                        }
                        languagesCard
                    }
                    AFMSectionLabel(text: "Local Data & Validation")
                    dataCard
                    if !appState.modelStatus.useCaseAvailability.isEmpty {
                        HStack(spacing: 8) {
                            AFMSectionLabel(text: "Specialized Models")
                            Spacer()
                        }
                        useCaseSection
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.green)
                        Text("On-device inference • Privacy and security kept local")
                            .font(.afmMono(10))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
                }
                .padding(18)
            }
        }
        .frame(width: 480, height: 520)
        .background(Color.afmWindow)
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.afmBlueLight)
                    .frame(width: 38, height: 38)
                Image(systemName: "cpu")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.afmBlue)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Model Diagnostics")
                    .font(.system(size: 13, weight: .semibold))
                Text(appState.modelStatus.title)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await appState.refreshModelStatus() }
            } label: {
                Label("Re-check", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.afmBlue)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.afmBlueLight, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            Button {
                dismiss()
            } label: {
                Text("Done")
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Color.afmSurface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.afmBorder)
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }

    private var statusHero: some View {
        let status = appState.modelStatus
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill((status.isAvailable ? Color.green : Color.orange).opacity(0.14))
                        .frame(width: 40, height: 40)
                    Image(systemName: status.isAvailable ? "checkmark" : "exclamationmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(status.isAvailable ? Color.green : Color.orange)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(status.isAvailable ? "Available" : "Unavailable")
                        .font(.system(size: 14, weight: .bold))
                    Text(status.detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            if !status.isOnDeviceProvider {
                mockBanner
            }
        }
        .padding(14)
        .background(Color.afmCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(status.isAvailable ? Color.green.opacity(0.25) : Color.orange.opacity(0.3))
        }
    }

    private var specGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            specTile("Maximum Context Window", value: contextWindowText, symbol: "text.magnifyingglass", tint: .blue)
            specTile("Languages", value: "\(appState.modelStatus.supportedLanguages.count) supported", symbol: "character.book.closed", tint: .green)
            specTile("Current Locale", value: localeText, symbol: "globe", tint: .teal)
            specTile("Data Source", value: appState.modelStatus.isOnDeviceProvider ? "Apple Foundation Model" : "Deterministic mock", symbol: "internaldrive", tint: appState.modelStatus.isOnDeviceProvider ? .green : .orange)
        }
    }

    private func specTile(_ title: String, value: String, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 11))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
        .background(Color.afmCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.afmBorder)
        }
    }

    private var fileTypesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Files that are eligible for workspace context")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            SupportedFileTypesTable()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.afmCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.afmBorder)
        }
    }

    private var languagesCard: some View {
        Text(appState.modelStatus.supportedLanguages.joined(separator: "  •  "))
            .font(.afmMono(10))
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.afmCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.afmBorder)
            }
    }

    private var dataCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            dataRow("Apple Intelligence", value: appState.modelStatus.isOnDeviceProvider ? "Enabled" : "Disabled", symbol: "cpu", dot: appState.modelStatus.isOnDeviceProvider ? .green : .orange)
            Divider().padding(.leading, 26)
            dataRow("Data source", value: appState.modelStatus.isOnDeviceProvider ? "On-device only" : "Local simulation", symbol: "internaldrive", dot: .secondary)
            Divider().padding(.leading, 26)
            dataRow("Last checked", value: appState.modelStatus.checkedAt.formatted(date: .abbreviated, time: .shortened), symbol: "clock", dot: .secondary)
        }
        .padding(4)
        .background(Color.afmCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.afmBorder)
        }
    }

    private func dataRow(_ title: String, value: String, symbol: String, dot: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Circle()
                .fill(dot)
                .frame(width: 5, height: 5)
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .textSelection(.enabled)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var mockBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "cpu")
                .foregroundStyle(.orange)
            Text("Mock Mode is active. This Mac isn't running Apple's on-device model, so the app uses deterministic simulated responses. Enable Apple Intelligence in System Settings to use the real on-device model.")
                .font(.system(size: 10))
                .foregroundStyle(.orange)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.2))
        }
    }

    private var useCaseSection: some View {
        let names = appState.modelStatus.useCaseAvailability.keys.sorted()
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(names.enumerated()), id: \.element) { _, name in
                let available = appState.modelStatus.useCaseAvailability[name] ?? false
                HStack(spacing: 8) {
                    Image(systemName: available ? "checkmark.circle.fill" : "xmark.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(available ? Color.green : Color.secondary)
                    Text(name)
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                    Text(available ? "available" : "unavailable")
                        .font(.system(size: 10))
                        .foregroundStyle(available ? Color.green : Color.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                if name != names.last {
                    Divider().padding(.leading, 26)
                }
            }
        }
        .padding(4)
        .background(Color.afmCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.afmBorder)
        }
    }

    private var contextWindowText: String {
        "\(appState.modelStatus.contextWindow) tokens"
    }

    private var localeText: String {
        let identifier = Locale.current.identifier
        let clean = identifier.split(separator: "@").first.map(String.init) ?? identifier
        let displayName = Locale.current.localizedString(forIdentifier: clean) ?? clean
        let supported = appState.modelStatus.currentLocaleSupported
        return "\(displayName) — \(supported ? "supported" : "not supported")"
    }
}