import SwiftUI

// MARK: - PacemakerSettingsView

/// Settings panel for the Pacemaker feature.
///
/// Pacemaker compares actual quota consumption against the theoretically
/// expected even-pace value within the active reset window. When actual usage
/// runs ahead of the expected pace by more than the configured thresholds,
/// warning or danger indicators appear in the menu bar popover.
struct PacemakerSettingsView: View {

    // MARK: State

    @State private var settings = PacemakerSettings.load()
    @EnvironmentObject private var viewModel: UsageViewModel

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                enableSection
                Divider()
                thresholdSection
                Divider()
                previewSection
                Spacer(minLength: 16)
            }
            .padding(20)
        }
        .onChange(of: settings.enabled)       { _, _ in settings.save() }
        .onChange(of: settings.warningDelta)  { _, _ in settings.save() }
        .onChange(of: settings.dangerDelta)   { _, _ in settings.save() }
    }

    // MARK: - Enable section

    private var enableSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(title: "Pacemaker", subtitle: "Track your usage against expected even pace")

            Toggle(isOn: $settings.enabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Enable Pacemaker")
                        .font(.callout)
                    Text("Shows a warning when you are consuming quota faster than the expected even pace for the current window.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
        }
    }

    // MARK: - Threshold section

    @ViewBuilder
    private var thresholdSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(title: "Thresholds", subtitle: nil)

            if !settings.enabled {
                Text("Enable Pacemaker to configure thresholds.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                // Warning threshold
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text("Warning")
                            .font(.callout.weight(.medium))
                        Spacer()
                        Text(String(format: "%.0f%%", settings.warningDelta * 100))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Slider(
                        value: $settings.warningDelta,
                        in: 0.05...0.50,
                        step: 0.05
                    ) {
                        EmptyView()
                    } minimumValueLabel: {
                        Text("5%").font(.caption2).foregroundStyle(.tertiary)
                    } maximumValueLabel: {
                        Text("50%").font(.caption2).foregroundStyle(.tertiary)
                    }
                    .onChange(of: settings.warningDelta) { _, newValue in
                        // Ensure warning < danger
                        if newValue >= settings.dangerDelta {
                            settings.dangerDelta = min(newValue + 0.05, 0.50)
                        }
                    }

                    Text("Shown when actual usage exceeds expected pace by this amount.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                // Danger threshold
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "exclamationmark.octagon.fill")
                            .foregroundStyle(.red)
                        Text("Danger")
                            .font(.callout.weight(.medium))
                        Spacer()
                        Text(String(format: "%.0f%%", settings.dangerDelta * 100))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Slider(
                        value: $settings.dangerDelta,
                        in: 0.10...0.50,
                        step: 0.05
                    ) {
                        EmptyView()
                    } minimumValueLabel: {
                        Text("10%").font(.caption2).foregroundStyle(.tertiary)
                    } maximumValueLabel: {
                        Text("50%").font(.caption2).foregroundStyle(.tertiary)
                    }
                    .onChange(of: settings.dangerDelta) { _, newValue in
                        // Ensure danger > warning
                        if newValue <= settings.warningDelta {
                            settings.warningDelta = max(newValue - 0.05, 0.05)
                        }
                    }

                    Text("Shown when actual usage exceeds expected pace by this amount.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Live preview section

    @ViewBuilder
    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Current Status", subtitle: "Live pacemaker evaluation")

            if !settings.enabled {
                Text("Enable Pacemaker to see live status.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                let quotaResults = viewModel.quotaResults
                if quotaResults.isEmpty {
                    Text("No quota data available. Add a service account to see pacemaker status.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 12)
                } else {
                    VStack(spacing: 8) {
                        ForEach(quotaResults, id: \.accountKey) { result in
                            ForEach(result.displayData.indices, id: \.self) { index in
                                if case .quota(let window) = result.displayData[index] {
                                    PacemakerStatusRow(
                                        service: result.serviceType,
                                        window: window,
                                        settings: settings
                                    )
                                }
                            }
                        }
                    }
                }
            }
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

// MARK: - PacemakerStatusRow

/// A single row in the live preview showing pacemaker status for one quota window.
private struct PacemakerStatusRow: View {

    let service: ServiceType
    let window: QuotaWindow
    let settings: PacemakerSettings

    private var status: PacemakerStatus {
        PacemakerStatus.evaluate(window: window, settings: settings)
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: service.iconSystemName)
                .foregroundStyle(service.color)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(service.shortName) — \(window.label)")
                    .font(.caption.weight(.medium))
                Text(String(format: "%.0f%% used", window.usedPercentage * 100))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            statusBadge
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch status {
        case .onTrack:
            Label("On Track", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)

        case .warning:
            Label(status.label, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.yellow)

        case .danger:
            Label(status.label, systemImage: "exclamationmark.octagon.fill")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Pacemaker Settings") {
    PacemakerSettingsView()
        .environmentObject(UsageViewModel(
            resultStore: UsageResultStore(),
            orchestrator: {
                let cs = CredentialStore(keychain: KeychainManager.shared)
                let api = APIClient.shared
                let factory = ProviderFactory(credentialStore: cs, apiClient: api)
                let ps = AccountProviderStore(accounts: [], factory: factory)
                let rs = UsageResultStore()
                let hs = UsageHistoryStore()
                return RefreshOrchestrator(providerStore: ps, resultStore: rs, historyStore: hs)
            }(),
            accountManager: {
                let cs = CredentialStore(keychain: KeychainManager.shared)
                let api = APIClient.shared
                let factory = ProviderFactory(credentialStore: cs, apiClient: api)
                let snapshot = AccountSnapshotLoader.loadSync()
                let ps = AccountProviderStore(accounts: snapshot.activeAccounts, factory: factory)
                let rs = UsageResultStore()
                let hs = UsageHistoryStore()
                let orc = RefreshOrchestrator(providerStore: ps, resultStore: rs, historyStore: hs)
                return AccountManager(snapshot: snapshot, providerStore: ps, credentialStore: cs, resultStore: rs, orchestrator: orc)
            }()
        ))
        .frame(width: 500, height: 500)
}
#endif
