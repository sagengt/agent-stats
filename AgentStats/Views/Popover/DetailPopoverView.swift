import SwiftUI

// MARK: - DetailPopoverView

/// A detailed popover showing all services with their accounts and full usage
/// breakdowns. Opened from `MenuBarContentView` via "Show Details".
///
/// Each service section renders:
/// - A header row with the service icon and display name.
/// - One account row per registered account, containing:
///   - Quota windows: donut chart + progress bar + reset time.
///   - Token summaries: input/output token counts with optional cost.
///   - Session activity: request count and total duration.
struct DetailPopoverView: View {

    @EnvironmentObject var viewModel: UsageViewModel

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Fixed header
            headerBar

            Divider()

            // Scrollable service sections
            if viewModel.results.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(viewModel.resultsByService, id: \.serviceType) { group in
                            ServiceSectionView(
                                serviceType: group.serviceType,
                                results: group.results,
                                showAccountLabels: group.results.count > 1,
                                viewModel: viewModel
                            )
                        }
                    }
                    .padding(12)
                }
            }
        }
        .frame(width: 340)
        .background(.regularMaterial)
    }

    // MARK: Header

    private var headerBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "chart.bar.doc.horizontal")
                .foregroundStyle(.blue)
                .font(.system(size: 14, weight: .semibold))

            Text("Usage Details")
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            if viewModel.isRefreshing {
                ProgressView()
                    .scaleEffect(0.65)
                    .frame(width: 16, height: 16)
            } else {
                Button {
                    viewModel.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Refresh now")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("No services configured")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Text("Add credentials in Settings.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}

// MARK: - ServiceSectionView

/// One collapsible section for a single service type.
private struct ServiceSectionView: View {

    let serviceType: ServiceType
    let results: [ServiceUsageResult]
    let showAccountLabels: Bool
    let viewModel: UsageViewModel

    @State private var isExpanded: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Section header (tappable to collapse/expand)
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    serviceType.iconImage
                        .foregroundStyle(serviceType.color)
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 18)

                    Text(serviceType.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(results) { result in
                        AccountDetailRow(
                            result: result,
                            accountLabel: showAccountLabels
                                ? viewModel.label(for: result.accountKey)
                                : nil
                        )
                    }
                }
                .padding(.leading, 24)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.04))
        )
    }
}

// MARK: - AccountDetailRow

/// Detailed usage display for a single account within a service section.
private struct AccountDetailRow: View {

    let result: ServiceUsageResult
    var accountLabel: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Optional per-account label
            if let label = accountLabel {
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(result.serviceType.color.opacity(0.12))
                    )
            }

            // Usage data items
            ForEach(Array(result.displayData.enumerated()), id: \.offset) { _, data in
                displayDataRow(data)
            }

            // Fetch timestamp
            Text("Updated \(result.fetchedAt, style: .relative) ago")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func displayDataRow(_ data: UsageDisplayData) -> some View {
        switch data {
        case .quota(let window):
            QuotaDetailRow(window: window, serviceColor: result.serviceType.color)

        case .tokenSummary(let summary):
            TokenDetailRow(summary: summary)

        case .activity(let activity):
            ActivityDetailRow(activity: activity)

        case .unavailable(let reason):
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                Text(reason.isEmpty ? "Data unavailable" : reason)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
}

// MARK: - QuotaDetailRow

/// Renders a single quota window with a donut + progress bar + reset time.
private struct QuotaDetailRow: View {

    let window: QuotaWindow
    let serviceColor: Color

    private var pctInt: Int { Int((window.usedPercentage * 100).rounded()) }

    var body: some View {
        HStack(spacing: 10) {
            // Donut chart
            UsageDonutView(
                usedPercentage: window.usedPercentage,
                size: 36,
                color: serviceColor
            )

            VStack(alignment: .leading, spacing: 3) {
                // Label + percentage
                HStack {
                    Text(window.label)
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                    Text("\(pctInt)%")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(quotaColor(for: window.usedPercentage))
                }

                // Progress bar
                UsageProgressBar(
                    percentage: window.usedPercentage,
                    height: 5
                )

                // Reset time
                if let resetAt = window.resetAt {
                    Text("Resets \(resetAt, style: .relative)")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(serviceColor.opacity(0.06))
        )
    }

    private func quotaColor(for pct: Double) -> Color {
        switch pct {
        case ..<0.5:  return .green
        case ..<0.8:  return .orange
        default:      return .red
        }
    }
}

// MARK: - TokenDetailRow

/// Renders input/output token counts and optional cost estimate.
private struct TokenDetailRow: View {

    let summary: TokenUsageSummary

    private var formattedTotal: String { formatTokens(summary.totalTokens) }
    private var formattedInput: String { formatTokens(summary.inputTokens) }
    private var formattedOutput: String { formatTokens(summary.outputTokens) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("\(formattedTotal) tokens", systemImage: "text.quote")
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                if let cost = summary.costUSD {
                    Text(String(format: "$%.4f", cost))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                tokenStat(label: "In", value: formattedInput)
                tokenStat(label: "Out", value: formattedOutput)
                Text(summary.period.rawValue.capitalized)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private func tokenStat(label: String, value: String) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}

// MARK: - ActivityDetailRow

/// Renders session activity metrics: requests, sessions, and duration.
private struct ActivityDetailRow: View {

    let activity: SessionActivity

    var body: some View {
        HStack(spacing: 12) {
            activityStat(
                value: "\(activity.requestCount)",
                label: "requests",
                icon: "arrow.up.arrow.down"
            )
            activityStat(
                value: "\(activity.activeSessions)",
                label: "sessions",
                icon: "terminal"
            )
            activityStat(
                value: formatDuration(activity.totalDurationMinutes),
                label: "total",
                icon: "clock"
            )
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private func activityStat(value: String, label: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func formatDuration(_ minutes: Int) -> String {
        if minutes >= 60 {
            let hours = minutes / 60
            let remaining = minutes % 60
            return remaining > 0 ? "\(hours)h\(remaining)m" : "\(hours)h"
        }
        return "\(minutes)m"
    }
}

// MARK: - Preview

#if DEBUG
private func makePreviewResult(service: ServiceType) -> ServiceUsageResult {
    var displayData: [UsageDisplayData] = []
    switch service {
    case .claude, .codex, .zai:
        displayData = [
            .quota(QuotaWindow(id: "5h", label: "5 Hour", usedPercentage: 0.72,
                               resetAt: Date().addingTimeInterval(3600))),
            .quota(QuotaWindow(id: "weekly", label: "Weekly", usedPercentage: 0.35,
                               resetAt: Date().addingTimeInterval(86400 * 4)))
        ]
    case .gemini, .copilot:
        displayData = [
            .tokenSummary(TokenUsageSummary(
                totalTokens: 1_450_000, inputTokens: 900_000, outputTokens: 550_000,
                costUSD: 2.18, period: .thisMonth
            ))
        ]
    case .cursor, .opencode:
        displayData = [
            .activity(SessionActivity(
                activeSessions: 2, totalDurationMinutes: 145, requestCount: 87,
                lastActiveAt: Date().addingTimeInterval(-300)
            ))
        ]
    }
    return ServiceUsageResult(
        accountKey: AccountKey(serviceType: service),
        displayData: displayData,
        fetchedAt: Date()
    )
}

#Preview("Detail Popover") {
    let vm = UsageViewModel(
        resultStore: UsageResultStore(),
        orchestrator: RefreshOrchestrator(
            providerStore: AccountProviderStore(accounts: [], factory: ProviderFactory(
                credentialStore: CredentialStore(keychain: KeychainManager.shared),
                apiClient: APIClient.shared
            )),
            resultStore: UsageResultStore(),
            historyStore: UsageHistoryStore()
        ),
        accountManager: AccountManager(
            snapshot: AccountSnapshot(),
            providerStore: AccountProviderStore(accounts: [], factory: ProviderFactory(
                credentialStore: CredentialStore(keychain: KeychainManager.shared),
                apiClient: APIClient.shared
            )),
            credentialStore: CredentialStore(keychain: KeychainManager.shared),
            resultStore: UsageResultStore(),
            orchestrator: RefreshOrchestrator(
                providerStore: AccountProviderStore(accounts: [], factory: ProviderFactory(
                    credentialStore: CredentialStore(keychain: KeychainManager.shared),
                    apiClient: APIClient.shared
                )),
                resultStore: UsageResultStore(),
                historyStore: UsageHistoryStore()
            )
        )
    )
    return DetailPopoverView()
        .environmentObject(vm)
}
#endif
