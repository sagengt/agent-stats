import SwiftUI

// MARK: - MenuBarContentView

/// The dropdown content shown when the user clicks the AgentStats menu bar icon.
///
/// Renders a compact list of service rows grouped by service type, with
/// per-account labels shown when a service has multiple accounts. Conforms
/// to the macOS Human Interface Guidelines for menu bar utilities.
struct MenuBarContentView: View {

    @EnvironmentObject var viewModel: UsageViewModel
    @EnvironmentObject var authCoordinator: AuthCoordinator

    @State private var showingDetailPopover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView
            Divider()
            serviceListView
            Divider()
            actionView
        }
        .padding(.vertical, 4)
        .frame(minWidth: 360, idealWidth: 400)
        .task {
            // Trigger initial refresh on first appearance.
            if viewModel.results.isEmpty {
                viewModel.refresh()
            }
        }
        .popover(isPresented: $showingDetailPopover, arrowEdge: .trailing) {
            DetailPopoverView()
                .environmentObject(viewModel)
        }
    }

    // MARK: Subviews

    @ViewBuilder
    private var headerView: some View {
        HStack(spacing: 6) {
            Image(systemName: "chart.bar.fill")
                .foregroundStyle(.blue)
                .font(.system(size: 13, weight: .semibold))

            Text("AgentStats")
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            if viewModel.isRefreshing {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 16, height: 16)
            } else {
                Text(viewModel.lastRefreshedDescription)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var serviceListView: some View {
        if viewModel.results.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "tray")
                    .font(.system(size: 24))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)

                Text("No services configured")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                Text("Add credentials in Settings.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(viewModel.resultsByService, id: \.serviceType) { group in
                    ForEach(group.results) { result in
                        ServiceRowView(
                            result: result,
                            accountLabel: viewModel.label(for: result.accountKey)
                        )
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var actionView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Show Details
            Button {
                showingDetailPopover = true
            } label: {
                Label("Show Details", systemImage: "chart.bar.doc.horizontal")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .disabled(viewModel.results.isEmpty)

            Button {
                viewModel.refresh()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .keyboardShortcut("r", modifiers: .command)
            .disabled(viewModel.isRefreshing)

            Divider()
                .padding(.vertical, 2)

            SettingsLink {
                Label("Settings...", systemImage: "gear")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .keyboardShortcut(",", modifiers: .command)
            .onAppear {
                // Ensure the app can show windows (menu bar apps are .accessory by default)
                NSApplication.shared.setActivationPolicy(.accessory)
            }

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit AgentStats", systemImage: "xmark.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .keyboardShortcut("q", modifiers: .command)
        }
    }
}

// MARK: - ServiceRowView

/// A single horizontal row summarising usage for one AI coding service account.
///
/// When `accountLabel` is non-nil it is displayed below the service name to
/// distinguish multiple accounts registered for the same service.
struct ServiceRowView: View {

    let result: ServiceUsageResult
    /// Optional human-readable label shown when a service has multiple accounts.
    var accountLabel: String?

    var body: some View {
        HStack(spacing: 8) {
            // Service icon
            result.serviceType.iconImage
                .foregroundStyle(result.serviceType.color)
                .font(.system(size: 13))
                .frame(width: 16)

            // Service name + optional account label
            VStack(alignment: .leading, spacing: 1) {
                Text(result.serviceType.shortName)
                    .font(.system(size: 12, weight: .medium))

                if let label = accountLabel {
                    Text(label)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(minWidth: 50, alignment: .leading)

            Spacer()

            // Usage data chips
            HStack(spacing: 6) {
                ForEach(Array(result.displayData.enumerated()), id: \.offset) { _, data in
                    displayDataView(data)
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.04))
        )
    }

    // MARK: Display data rendering

    @ViewBuilder
    private func displayDataView(_ data: UsageDisplayData) -> some View {
        switch data {
        case .quota(let window):
            quotaChip(window)

        case .tokenSummary(let summary):
            tokenChip(summary)

        case .activity(let activity):
            activityChip(activity)

        case .unavailable(let reason):
            Text(reason.isEmpty ? "–" : reason)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    @ViewBuilder
    private func quotaChip(_ window: QuotaWindow) -> some View {
        let pct = window.usedPercentage
        let pctInt = Int((pct * 100).rounded())

        HStack(spacing: 3) {
            Text(window.label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            Text("\(pctInt)%")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(quotaColor(for: pct))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(quotaColor(for: pct).opacity(0.12))
        )
    }

    @ViewBuilder
    private func tokenChip(_ summary: TokenUsageSummary) -> some View {
        let kTokens = summary.totalTokens / 1000
        Text("\(kTokens)K tokens")
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func activityChip(_ activity: SessionActivity) -> some View {
        HStack(spacing: 3) {
            Text("\(activity.requestCount)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
            Text("req")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Helpers

    private func quotaColor(for percentage: Double) -> Color {
        switch percentage {
        case ..<0.5:  return .green
        case ..<0.8:  return .orange
        default:      return .red
        }
    }
}
