import SwiftUI

// MARK: - UsageHistoryTabView

/// Full history analytics tab showing heatmap, trend chart, cycle view, and summary stats.
///
/// Intended to be hosted inside a settings/detail window tab group.
/// Hosts a `UsageHistoryViewModel` and drives all child chart views.
struct UsageHistoryTabView: View {

    @StateObject private var historyVM: UsageHistoryViewModel

    // MARK: Init

    init(historyStore: UsageHistoryStoreProtocol) {
        _historyVM = StateObject(wrappedValue: UsageHistoryViewModel(historyStore: historyStore))
    }

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                filterBar
                Divider()
                heatmapSection
                Divider()
                trendSection
                Divider()
                HStack(alignment: .top, spacing: 24) {
                    cycleSection
                    Spacer()
                    summarySection
                }
                Spacer(minLength: 20)
            }
            .padding(20)
        }
        .task {
            historyVM.loadData()
        }
        .onChange(of: historyVM.selectedService) { _, _ in historyVM.loadData() }
        .onChange(of: historyVM.selectedAccountKey) { _, _ in historyVM.loadData() }
        .onChange(of: historyVM.dateRange) { _, _ in historyVM.loadData() }
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        HStack(spacing: 12) {
            // Service picker
            Picker("Service", selection: $historyVM.selectedService) {
                Text("All Services").tag(Optional<ServiceType>.none)
                ForEach(historyVM.availableServices) { service in
                    Label(service.displayName, systemImage: service.iconSystemName)
                        .tag(Optional(service))
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 180)
            .labelsHidden()
            .help("Filter by service")

            // Date range segmented control
            Picker("Range", selection: $historyVM.dateRange) {
                ForEach(DateRange.allCases) { range in
                    Text(range.label).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 280)
            .help("Select date range")

            Spacer()

            if historyVM.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    // MARK: - Heatmap section

    private var heatmapSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(
                title: "Daily Activity",
                subtitle: "\(historyVM.summary.totalDays) active days"
            )

            if historyVM.heatmapData.isEmpty && !historyVM.isLoading {
                emptyStateView(message: "No history data available yet.")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HeatmapView(
                        cells: historyVM.heatmapData,
                        columns: historyVM.dateRange.days / 7,
                        cellColor: selectedColor
                    )
                    .padding(.bottom, 4)
                }
            }
        }
    }

    // MARK: - Trend section

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(
                title: "Usage Trend",
                subtitle: historyVM.dateRange.label
            )

            if historyVM.trendData.isEmpty && !historyVM.isLoading {
                emptyStateView(message: "No trend data available yet.")
            } else {
                TrendChartView(
                    points: historyVM.trendData,
                    lineColor: selectedColor
                )
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Cycle section

    private var cycleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(
                title: "Weekly Pattern",
                subtitle: "Average by day of week"
            )

            if historyVM.cycleData.isEmpty && !historyVM.isLoading {
                emptyStateView(message: "Not enough data.")
            } else {
                CycleHeatmapView(
                    cells: historyVM.cycleData,
                    barColor: selectedColor
                )
            }
        }
    }

    // MARK: - Summary section

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "Summary", subtitle: nil)

            statRow(label: "Peak Usage", value: formattedPeakValue)
            statRow(label: "Peak Date", value: formattedPeakDate)
            statRow(label: "Average", value: formattedAverage)
            statRow(label: "Current Streak", value: "\(historyVM.summary.currentStreak) day\(historyVM.summary.currentStreak == 1 ? "" : "s")")
            statRow(label: "Active Days", value: "\(historyVM.summary.totalDays)")
        }
        .frame(minWidth: 160)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    // MARK: - Reusable subviews

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

    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
        }
    }

    private func emptyStateView(message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 20)
    }

    // MARK: - Helpers

    private var selectedColor: Color {
        historyVM.selectedService?.color ?? .accentColor
    }

    private var formattedPeakValue: String {
        let v = historyVM.summary.peakValue
        return v > 0 ? String(format: "%.0f%%", v * 100) : "—"
    }

    private var formattedPeakDate: String {
        guard let date = historyVM.summary.peakDate else { return "—" }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: date)
    }

    private var formattedAverage: String {
        let v = historyVM.summary.averageValue
        return v > 0 ? String(format: "%.0f%%", v * 100) : "—"
    }
}

// MARK: - Preview

#if DEBUG
private final class PreviewHistoryStore: UsageHistoryStoreProtocol, @unchecked Sendable {
    func record(results: [ServiceUsageResult]) async {}
    func records(for service: ServiceType, accountKey: AccountKey?, since: Date, until: Date) async -> [UsageHistoryRecord] { [] }
    func availableServices() async -> [ServiceType] { [.claude, .codex] }
}

#Preview("UsageHistoryTabView") {
    UsageHistoryTabView(historyStore: PreviewHistoryStore())
        .frame(width: 700, height: 600)
}
#endif
