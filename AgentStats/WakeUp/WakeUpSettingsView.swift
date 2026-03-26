import SwiftUI

// MARK: - WakeUpSettingsView

/// Settings panel for the WakeUp scheduler.
///
/// Allows the user to install or remove the LaunchAgent that wakes
/// AgentStats at specified hours so quota data is refreshed on schedule
/// even when the app was not running.
struct WakeUpSettingsView: View {

    // MARK: State

    @State private var enabled: Bool = WakeUpScheduler.isInstalled()
    @State private var selectedHours: Set<Int> = Set(WakeUpScheduler.installedHours())
    @State private var errorMessage: String? = nil
    @State private var isApplying: Bool = false

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                enableSection
                Divider()
                hourGridSection
                Divider()
                applySection
                Spacer(minLength: 16)
            }
            .padding(20)
        }
    }

    // MARK: - Enable section

    private var enableSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(title: "WakeUp Scheduler", subtitle: "Refresh quota data at scheduled times")

            Toggle(isOn: $enabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Enable WakeUp Scheduler")
                        .font(.callout)
                    Text("Installs a LaunchAgent that opens AgentStats at the selected hours, ensuring quota data is always fresh.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .onChange(of: enabled) { _, newValue in
                if !newValue {
                    selectedHours = []
                } else if selectedHours.isEmpty {
                    // Default to 9 AM when first enabling.
                    selectedHours = [9]
                }
            }
        }
    }

    // MARK: - Hour grid section

    @ViewBuilder
    private var hourGridSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionHeader(title: "Scheduled Hours", subtitle: "(local time)")
                Spacer()
                Text("\(selectedHours.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !enabled {
                Text("Enable the scheduler to select hours.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                hourGrid
                    .padding(.top, 4)

                HStack(spacing: 12) {
                    Button("Select All") {
                        selectedHours = Set(0...23)
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)

                    Button("Clear") {
                        selectedHours = []
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)

                    Button("Every 6h") {
                        selectedHours = [0, 6, 12, 18]
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)

                    Button("Business Hours") {
                        selectedHours = Set(9...17)
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }
        }
    }

    /// 24-button grid, 6 columns × 4 rows, showing each hour 00–23.
    private var hourGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6),
            spacing: 6
        ) {
            ForEach(0..<24) { hour in
                HourCell(
                    hour: hour,
                    isSelected: selectedHours.contains(hour),
                    isEnabled: enabled
                ) {
                    if selectedHours.contains(hour) {
                        selectedHours.remove(hour)
                    } else {
                        selectedHours.insert(hour)
                    }
                }
            }
        }
    }

    // MARK: - Apply section

    @ViewBuilder
    private var applySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let error = errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            HStack(spacing: 12) {
                Button {
                    applyChanges()
                } label: {
                    if isApplying {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 80)
                    } else {
                        Text(enabled ? "Install / Update" : "Uninstall")
                            .frame(minWidth: 80)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isApplying)

                if WakeUpScheduler.isInstalled() && !enabled {
                    Text("The LaunchAgent is currently installed. Click Uninstall to remove it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if enabled && selectedHours.isEmpty {
                    Text("Select at least one hour to install the scheduler.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            if WakeUpScheduler.isInstalled() {
                let hours = WakeUpScheduler.installedHours()
                let formatted = hours.map { String(format: "%02d:00", $0) }.joined(separator: ", ")
                Text("Currently installed at: \(formatted.isEmpty ? "—" : formatted)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Actions

    private func applyChanges() {
        errorMessage = nil
        isApplying = true

        // Capture values before entering the Task to avoid actor-isolation warnings.
        let shouldInstall = enabled && !selectedHours.isEmpty
        let hours = Array(selectedHours)

        Task(priority: .userInitiated) {
            do {
                if shouldInstall {
                    try await Task.detached { try WakeUpScheduler.install(hours: hours) }.value
                } else {
                    try await Task.detached { try WakeUpScheduler.uninstall() }.value
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isApplying = false
        }
    }

    // MARK: - Helpers

    private func sectionHeader(title: String, subtitle: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(.headline)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - HourCell

/// A single toggleable hour cell in the 24-hour grid.
private struct HourCell: View {

    let hour: Int
    let isSelected: Bool
    let isEnabled: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(String(format: "%02d", hour))
                .font(.system(.caption, design: .monospaced))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isSelected ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                )
                .foregroundStyle(isSelected ? Color.white : (isEnabled ? Color.primary : Color.secondary.opacity(0.5)))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("WakeUp Settings") {
    WakeUpSettingsView()
        .frame(width: 500, height: 520)
}
#endif
