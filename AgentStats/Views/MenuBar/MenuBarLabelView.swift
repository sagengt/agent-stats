import SwiftUI

// MARK: - MenuBarLabelView

/// The icon and optional text shown in the macOS menu bar.
///
/// When at least one service result is available the label displays the
/// usage percentage of the most-consumed quota window so the user can
/// glance at overall status without opening the popover. The icon tint
/// shifts from green to orange to red as consumption climbs.
struct MenuBarLabelView: View {

    let results: [ServiceUsageResult]

    // MARK: Body

    var body: some View {
        if let topQuotaWindow = highestUsageQuotaWindow {
            Label {
                Text(percentageText(for: topQuotaWindow))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
            } icon: {
                Image(systemName: "chart.bar.fill")
                    .foregroundStyle(tintColor(for: topQuotaWindow.usedPercentage))
            }
        } else if !results.isEmpty {
            // Results exist but none have quota windows (e.g. token/activity-only services).
            // Show the unique service count across all accounts.
            let serviceCount = Set(results.map(\.serviceType)).count
            Label {
                Text(serviceCount == 1
                     ? results[0].serviceType.shortName
                     : "\(serviceCount)")
            } icon: {
                Image(systemName: "chart.bar.fill")
            }
        } else {
            // No data yet — show the bare app icon.
            Label("AgentStats", systemImage: "chart.bar.fill")
                .labelStyle(.iconOnly)
        }
    }

    // MARK: Private helpers

    /// The quota window with the highest usage across all results.
    private var highestUsageQuotaWindow: QuotaWindow? {
        results
            .flatMap { result in
                result.displayData.compactMap { item -> QuotaWindow? in
                    if case .quota(let window) = item { return window }
                    return nil
                }
            }
            .max(by: { $0.usedPercentage < $1.usedPercentage })
    }

    private func percentageText(for window: QuotaWindow) -> String {
        let pct = Int((window.usedPercentage * 100).rounded())
        return "\(pct)%"
    }

    private func tintColor(for percentage: Double) -> Color {
        switch percentage {
        case ..<0.5:  return .green
        case ..<0.8:  return .orange
        default:      return .red
        }
    }

    private func summaryText(for result: ServiceUsageResult) -> String {
        for item in result.displayData {
            switch item {
            case .quota(let window):
                let pct = Int((window.usedPercentage * 100).rounded())
                return "\(result.serviceType.shortName) \(pct)%"
            case .tokenSummary(let summary):
                return "\(result.serviceType.shortName) \(summary.totalTokens / 1000)K"
            case .activity(let activity):
                return "\(result.serviceType.shortName) \(activity.requestCount)req"
            case .unavailable:
                continue
            }
        }
        return result.serviceType.shortName
    }
}
