import Foundation
import WidgetKit

// MARK: - WidgetAggregatedEntry

/// Codable DTO that mirrors `AggregatedUsageResult` for cross-process
/// Widget sharing via an App Group `UserDefaults` suite.
///
/// `AggregatedUsageResult` itself is not `Codable` because `UsageDisplayData`
/// is not `Codable`. This flat DTO captures only the data that the Widget
/// actually needs to render quota bars and token summaries.
struct WidgetAggregatedEntry: Codable, Sendable, Identifiable {

    let serviceType: ServiceType
    let aggregatedAt: Date
    let sourceAccountCount: Int

    /// Quota windows extracted from `.quota(_)` display data items.
    let quotaWindows: [QuotaWindow]

    /// Token summaries extracted from `.tokenSummary(_)` display data items.
    let tokenSummaries: [TokenUsageSummary]

    /// Session activities extracted from `.activity(_)` display data items.
    let sessionActivities: [SessionActivity]

    /// The first unavailability reason, if any display item is `.unavailable`.
    let unavailableReason: String?

    var id: ServiceType { serviceType }

    // MARK: Init from AggregatedUsageResult

    init(from result: AggregatedUsageResult) {
        self.serviceType = result.serviceType
        self.aggregatedAt = result.aggregatedAt
        self.sourceAccountCount = result.sourceAccountCount

        var quotas: [QuotaWindow] = []
        var tokens: [TokenUsageSummary] = []
        var activities: [SessionActivity] = []
        var firstUnavailable: String? = nil

        for item in result.displayData {
            switch item {
            case .quota(let window):
                quotas.append(window)
            case .tokenSummary(let summary):
                tokens.append(summary)
            case .activity(let activity):
                activities.append(activity)
            case .unavailable(let reason):
                if firstUnavailable == nil { firstUnavailable = reason }
            }
        }

        self.quotaWindows = quotas
        self.tokenSummaries = tokens
        self.sessionActivities = activities
        self.unavailableReason = firstUnavailable
    }
}

// MARK: - WidgetExportStore

/// Actor that persists aggregated usage data to a shared App Group `UserDefaults`
/// suite so that a WidgetKit extension can read the latest quota snapshots
/// without requiring an XPC connection to the main app.
///
/// The Widget extension reads from the same suite using `WidgetExportStore.loadAggregated()`.
/// Call `WidgetKit.WidgetCenter.shared.reloadAllTimelines()` after `update(aggregated:)`
/// to prompt the system to re-render widget views immediately.
actor WidgetExportStore {

    // MARK: Constants

    private let suiteName = "group.com.agentstats"
    private let key = "widget.aggregated"

    // MARK: Shared UserDefaults

    private var defaults: UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }

    // MARK: - Write

    /// Encodes `aggregated` as JSON and stores it in the shared App Group suite.
    ///
    /// After persisting, this method signals WidgetKit to reload all timelines
    /// so widget views immediately reflect the new data.
    ///
    /// - Parameter aggregated: The latest aggregated results produced by
    ///   `UsageViewModel` or `RefreshOrchestrator`.
    func update(aggregated: [AggregatedUsageResult]) async {
        let entries = aggregated.map { WidgetAggregatedEntry(from: $0) }
        do {
            let data = try JSONEncoder().encode(entries)
            defaults?.set(data, forKey: key)
            // Reload WidgetKit timelines so the Widget picks up new data immediately.
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            // Encoding failure is non-fatal — widget will show stale data until
            // the next successful update.
        }
    }

    // MARK: - Read

    /// Loads the most recently stored aggregated entries from the shared suite.
    ///
    /// This method is safe to call from the Widget extension process, which
    /// shares the same App Group container.
    ///
    /// - Returns: The stored entries, or an empty array when no data has been
    ///   written yet or the stored JSON cannot be decoded.
    func loadAggregated() async -> [WidgetAggregatedEntry] {
        guard
            let data = defaults?.data(forKey: key),
            let entries = try? JSONDecoder().decode([WidgetAggregatedEntry].self, from: data)
        else {
            return []
        }
        return entries
    }

    // MARK: - Synchronous read (Widget extension entry point)

    /// Synchronous variant of `loadAggregated()` for use from WidgetKit
    /// `TimelineProvider.getTimeline(_:in:completion:)` which runs on a
    /// background thread outside the actor system.
    ///
    /// - Returns: Decoded entries, or empty array on failure.
    nonisolated func loadAggregatedSync() -> [WidgetAggregatedEntry] {
        guard
            let defaults = UserDefaults(suiteName: suiteName),
            let data = defaults.data(forKey: key),
            let entries = try? JSONDecoder().decode([WidgetAggregatedEntry].self, from: data)
        else {
            return []
        }
        return entries
    }
}
