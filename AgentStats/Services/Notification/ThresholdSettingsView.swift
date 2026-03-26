import SwiftUI
import UserNotifications

// MARK: - ThresholdSettingsView

/// Settings panel for configuring quota threshold notifications.
///
/// Allows the user to enable/disable notifications, adjust the warning and
/// danger percentage sliders, and fire a test notification to verify delivery.
struct ThresholdSettingsView: View {

    // MARK: State

    @State private var config: ThresholdNotificationManager.ThresholdConfig = .init()
    @State private var isAuthorized: Bool = false
    @State private var showPermissionAlert: Bool = false
    @State private var testSent: Bool = false

    // MARK: Private

    private let manager: ThresholdNotificationManager = ThresholdNotificationManager()

    // MARK: Body

    var body: some View {
        Form {
            Section {
                enableSection
            } header: {
                Text("Threshold Notifications")
                    .font(.headline)
            }

            Divider()
                .padding(.vertical, 4)

            Section {
                thresholdSection
            } header: {
                Text("Thresholds")
                    .font(.headline)
            }
            .disabled(!config.enabled)

            Divider()
                .padding(.vertical, 4)

            Section {
                testSection
            } header: {
                Text("Test")
                    .font(.headline)
            }
            .disabled(!config.enabled || !isAuthorized)
        }
        .formStyle(.grouped)
        .padding(20)
        .task {
            await loadState()
        }
        .alert("Notification Permission Required", isPresented: $showPermissionAlert) {
            Button("Open System Settings") {
                openNotificationSettings()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("AgentStats needs notification permission to send threshold alerts. Please enable it in System Settings > Notifications.")
        }
    }

    // MARK: Enable section

    @ViewBuilder
    private var enableSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $config.enabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Enable Notifications")
                        .font(.callout)
                    Text("Receive alerts when quota usage crosses warning or danger thresholds.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .onChange(of: config.enabled) { _, newValue in
                if newValue && !isAuthorized {
                    Task { await requestPermissionIfNeeded() }
                } else {
                    saveConfig()
                }
            }

            if !isAuthorized && config.enabled {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Text("Notification permission not granted.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Button("Grant Access") {
                        Task { await requestPermissionIfNeeded() }
                    }
                    .font(.caption)
                    .buttonStyle(.link)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: Threshold section

    @ViewBuilder
    private var thresholdSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            thresholdRow(
                label: "Warning Threshold",
                description: "Alert when usage reaches this level.",
                value: $config.warningThreshold,
                range: 0.5...0.95,
                color: .orange
            )

            Divider()

            thresholdRow(
                label: "Danger Threshold",
                description: "Critical alert when usage reaches this level.",
                value: $config.dangerThreshold,
                range: 0.7...0.99,
                color: .red
            )
        }
        .padding(.vertical, 4)
        .onChange(of: config.warningThreshold) { _, _ in clampThresholds(); saveConfig() }
        .onChange(of: config.dangerThreshold) { _, _ in clampThresholds(); saveConfig() }
    }

    private func thresholdRow(
        label: String,
        description: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.callout)
                Spacer()
                Text("\(Int(value.wrappedValue * 100))%")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(color)
                    .frame(width: 40, alignment: .trailing)
            }

            Slider(value: value, in: range, step: 0.01) {
                EmptyView()
            } minimumValueLabel: {
                Text("\(Int(range.lowerBound * 100))%")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } maximumValueLabel: {
                Text("\(Int(range.upperBound * 100))%")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .tint(color)

            Text(description)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: Test section

    @ViewBuilder
    private var testSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Send Test Notification")
                    .font(.callout)
                Text("Verify that notifications appear correctly on your system.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if testSent {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .transition(.scale.combined(with: .opacity))
            }
            Button("Test") {
                sendTest()
            }
            .buttonStyle(.borderedProminent)
            .disabled(testSent)
        }
        .padding(.vertical, 4)
        .animation(.easeInOut(duration: 0.2), value: testSent)
    }

    // MARK: Helpers

    private func loadState() async {
        let loaded = await manager.currentConfig()
        config = loaded

        let settings = await UNUserNotificationCenter.current().notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized
    }

    private func saveConfig() {
        let captured = config
        Task { await manager.updateConfig(captured) }
    }

    private func requestPermissionIfNeeded() async {
        let granted = await ThresholdNotificationManager.requestAuthorization()
        isAuthorized = granted
        if !granted {
            showPermissionAlert = true
            config.enabled = false
        } else {
            saveConfig()
        }
    }

    private func sendTest() {
        Task {
            await manager.sendTestNotification()
            testSent = true
            try? await Task.sleep(for: .seconds(3))
            testSent = false
        }
    }

    /// Ensures warning threshold never exceeds danger threshold.
    private func clampThresholds() {
        if config.warningThreshold >= config.dangerThreshold {
            config.dangerThreshold = min(0.99, config.warningThreshold + 0.05)
        }
    }

    private func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Threshold Settings") {
    ThresholdSettingsView()
        .frame(width: 500, height: 480)
}
#endif
