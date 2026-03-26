import SwiftUI
import ServiceManagement

// MARK: - GeneralSettingsTab

/// General preferences: menu bar display style, refresh interval, login item,
/// and language selection.
struct GeneralSettingsTab: View {

    // MARK: Environment

    @EnvironmentObject private var languageManager: LanguageManager

    // MARK: Stored preferences

    @AppStorage(MenuBarDisplayModeKey.userDefaultsKey)
    private var displayModeRaw: String = MenuBarDisplayMode.label.rawValue

    @AppStorage("agentstats.refreshInterval")
    private var refreshIntervalMinutes: Double = 5.0

    @AppStorage("agentstats.launchAtLogin")
    private var launchAtLogin: Bool = false

    // MARK: Computed

    private var displayMode: Binding<MenuBarDisplayMode> {
        Binding(
            get: { MenuBarDisplayMode(rawValue: displayModeRaw) ?? .label },
            set: { displayModeRaw = $0.rawValue }
        )
    }

    // MARK: Body

    var body: some View {
        Form {
            // Menu bar appearance
            Section {
                displayModeSection
            } header: {
                Text("Menu Bar Appearance")
                    .font(.headline)
            }

            Divider()
                .padding(.vertical, 4)

            // Auto-refresh
            Section {
                refreshSection
            } header: {
                Text("Auto-Refresh")
                    .font(.headline)
            }

            Divider()
                .padding(.vertical, 4)

            // System integration
            Section {
                launchSection
            } header: {
                Text("System")
                    .font(.headline)
            }

        }
        .formStyle(.grouped)
        .padding(20)
    }

    // MARK: Display mode section

    @ViewBuilder
    private var displayModeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose how usage data appears in the menu bar.")
                .font(.callout)
                .foregroundStyle(.secondary)

            // Mode tiles
            HStack(spacing: 8) {
                ForEach(MenuBarDisplayMode.allCases) { mode in
                    displayModeTile(mode: mode, isSelected: displayMode.wrappedValue == mode)
                }
            }

            // Description of current mode
            Text(displayMode.wrappedValue.description)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private func displayModeTile(mode: MenuBarDisplayMode, isSelected: Bool) -> some View {
        Button {
            displayMode.wrappedValue = mode
            MenuBarDisplayModeKey.save(mode)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: mode.iconSystemName)
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? .white : .primary)
                Text(mode.displayName)
                    .font(.caption)
                    .foregroundStyle(isSelected ? .white : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.07))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Refresh section

    @ViewBuilder
    private var refreshSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Every \(Int(refreshIntervalMinutes)) minute\(refreshIntervalMinutes == 1 ? "" : "s")")
                    .font(.callout)
                Spacer()
                Text("Refresh Interval")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Slider(
                value: $refreshIntervalMinutes,
                in: 1...10,
                step: 1
            ) {
                EmptyView()
            } minimumValueLabel: {
                Text("1m")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } maximumValueLabel: {
                Text("10m")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: Launch section

    @ViewBuilder
    private var launchSection: some View {
        Toggle(isOn: $launchAtLogin) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Launch at Login")
                    .font(.callout)
                Text("AgentStats will start automatically when you log in.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
        .onChange(of: launchAtLogin) { _, newValue in
            applyLaunchAtLogin(enabled: newValue)
        }
        .padding(.vertical, 4)
    }

    // MARK: Language section

    @ViewBuilder
    private var languageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Choose the display language for AgentStats.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Picker("Language", selection: $languageManager.currentLanguage) {
                ForEach(AppLanguage.allCases) { lang in
                    Text(lang.displayName).tag(lang)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text("Changing the language takes effect immediately.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    // MARK: Helpers

    private func applyLaunchAtLogin(enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // Silently tolerate — user can manage via System Settings.
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("General Settings") {
    GeneralSettingsTab()
        .environmentObject(LanguageManager.shared)
        .frame(width: 500, height: 480)
}
#endif
