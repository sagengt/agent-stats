import Foundation
import SwiftUI

// MARK: - DateRange

/// Predefined time windows available in the history analytics UI.
enum DateRange: String, CaseIterable, Identifiable {
    case last7Days  = "7 Days"
    case last30Days = "30 Days"
    case last90Days = "90 Days"
    case lastYear   = "1 Year"

    var id: String { rawValue }

    /// Human-readable label.
    var label: String { rawValue }

    /// Number of calendar days the range covers.
    var days: Int {
        switch self {
        case .last7Days:  return 7
        case .last30Days: return 30
        case .last90Days: return 90
        case .lastYear:   return 365
        }
    }

    /// The start date for this range relative to now.
    var startDate: Date {
        Calendar.current.date(byAdding: .day, value: -(days - 1), to: Calendar.current.startOfDay(for: Date())) ?? Date()
    }

    /// The end date for this range (end of today).
    var endDate: Date {
        let start = Calendar.current.startOfDay(for: Date())
        return Calendar.current.date(byAdding: .day, value: 1, to: start).map { $0.addingTimeInterval(-1) } ?? Date()
    }
}

// MARK: - HeatmapCell

/// One cell in the GitHub-style contribution heatmap. Represents a single calendar day.
struct HeatmapCell: Identifiable {
    /// The calendar day this cell represents.
    let id: Date

    /// Normalized intensity in `0.0 – 1.0`. `0.0` means no data recorded.
    let value: Double

    /// Number of records captured on this day (for tooltip display).
    let recordCount: Int
}

// MARK: - TrendPoint

/// A single data point on the usage trend line chart.
struct TrendPoint: Identifiable {
    /// The calendar day this point represents.
    let id: Date

    /// The value to plot (quota percentage, token count, or session count).
    let value: Double
}

// MARK: - SummaryStats

/// Computed aggregate statistics shown below the charts.
struct SummaryStats {
    let peakDate: Date?
    let peakValue: Double
    let averageValue: Double
    let currentStreak: Int   // consecutive days with at least one record
    let totalDays: Int       // days with any recorded data in the selected range
}

// MARK: - UsageHistoryViewModel

/// Drives the history analytics UI by loading and transforming `UsageHistoryRecord`
/// data from the persistent store into chart-ready value objects.
@MainActor
final class UsageHistoryViewModel: ObservableObject {

    // MARK: Published state

    /// Cells for the GitHub-style daily heatmap (365 days max).
    @Published var heatmapData: [HeatmapCell] = []

    /// Points for the line trend chart.
    @Published var trendData: [TrendPoint] = []

    /// Cells for the 7-day cycle consistency view (indexed Monday–Sunday).
    @Published var cycleData: [HeatmapCell] = []

    /// Selected service filter; `nil` means "all services".
    @Published var selectedService: ServiceType? = nil

    /// Selected account filter; `nil` means "all accounts for selected service".
    @Published var selectedAccountKey: AccountKey? = nil

    /// Currently active date range.
    @Published var dateRange: DateRange = .last30Days

    /// Available services for the filter picker (populated from store).
    @Published var availableServices: [ServiceType] = []

    /// `true` while an async load is in progress.
    @Published var isLoading: Bool = false

    /// Aggregate statistics for the current selection.
    @Published var summary: SummaryStats = SummaryStats(
        peakDate: nil, peakValue: 0, averageValue: 0, currentStreak: 0, totalDays: 0
    )

    // MARK: Dependencies

    private let historyStore: UsageHistoryStoreProtocol

    // MARK: Private state

    private var loadTask: Task<Void, Never>?

    // MARK: Init

    init(historyStore: UsageHistoryStoreProtocol) {
        self.historyStore = historyStore
    }

    // MARK: Public API

    /// Triggers an async reload of all chart data from the persistent store.
    /// Cancels any in-flight load before starting a new one.
    func loadData() {
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }
            self.isLoading = true
            defer { self.isLoading = false }

            await self.reloadAvailableServices()

            guard !Task.isCancelled else { return }

            await self.reloadChartData()
        }
    }

    // MARK: Private - data loading

    private func reloadAvailableServices() async {
        let services = await historyStore.availableServices()
        availableServices = services
        // If the current selection is no longer available, reset it.
        if let selected = selectedService, !services.contains(selected) {
            selectedService = nil
            selectedAccountKey = nil
        }
    }

    private func reloadChartData() async {
        guard let service = selectedService else {
            // No service selected: aggregate across all available services.
            let dailyValues = await aggregateAllServices()
            applyDailyValues(dailyValues)
            return
        }

        let records = await historyStore.records(
            for: service,
            accountKey: selectedAccountKey,
            since: dateRange.startDate,
            until: dateRange.endDate
        )

        guard !Task.isCancelled else { return }

        let dailyValues = groupByDay(records: records, service: service)
        applyDailyValues(dailyValues)
    }

    /// Aggregates records across all available services into per-day representative values.
    private func aggregateAllServices() async -> [Date: (value: Double, count: Int)] {
        var combined: [Date: (value: Double, count: Int)] = [:]

        for service in availableServices {
            let records = await historyStore.records(
                for: service,
                accountKey: nil,
                since: dateRange.startDate,
                until: dateRange.endDate
            )
            guard !Task.isCancelled else { return combined }

            let dayValues = groupByDay(records: records, service: service)
            for (day, entry) in dayValues {
                if let existing = combined[day] {
                    // Average across services for the same day.
                    let totalCount = existing.count + entry.count
                    let mergedValue = (existing.value * Double(existing.count) + entry.value * Double(entry.count))
                        / Double(totalCount)
                    combined[day] = (value: mergedValue, count: totalCount)
                } else {
                    combined[day] = entry
                }
            }
        }
        return combined
    }

    /// Groups records by calendar day, extracting a representative display value per day.
    private func groupByDay(
        records: [UsageHistoryRecord],
        service: ServiceType
    ) -> [Date: (value: Double, count: Int)] {
        var groups: [Date: [UsageHistoryRecord]] = [:]
        let cal = Calendar.current

        for record in records {
            let day = cal.startOfDay(for: record.recordedAt)
            groups[day, default: []].append(record)
        }

        var result: [Date: (value: Double, count: Int)] = [:]
        for (day, dayRecords) in groups {
            let value = representativeValue(for: dayRecords)
            result[day] = (value: value, count: dayRecords.count)
        }
        return result
    }

    /// Extracts a single representative `0.0–1.0` value from a set of records.
    ///
    /// Priority: quota percentage > token count (normalised) > session activity.
    private func representativeValue(for records: [UsageHistoryRecord]) -> Double {
        // Use the last record of the day as the most current snapshot.
        guard let last = records.max(by: { $0.recordedAt < $1.recordedAt }) else { return 0 }

        for data in last.displayData {
            switch data {
            case .quota(let window):
                return min(window.usedPercentage, 1.0)
            case .tokenSummary(let summary):
                // Normalise to a rough cap of 1 million tokens = 1.0.
                return min(Double(summary.totalTokens) / 1_000_000.0, 1.0)
            case .activity(let session):
                // Normalise to a rough cap of 8 hours = 1.0.
                return min(Double(session.totalDurationMinutes) / 480.0, 1.0)
            case .unavailable:
                continue
            }
        }
        return 0
    }

    /// Converts day-value pairs into published chart data and summary statistics.
    private func applyDailyValues(_ dailyValues: [Date: (value: Double, count: Int)]) {
        let cal = Calendar.current
        let allDays = enumerateDays(from: dateRange.startDate, to: dateRange.endDate)

        // Find the global max for normalisation (heat intensity).
        let maxValue = dailyValues.values.map(\.value).max() ?? 1.0
        let normDenominator = maxValue > 0 ? maxValue : 1.0

        // Build heatmap.
        heatmapData = allDays.map { day in
            if let entry = dailyValues[day] {
                return HeatmapCell(
                    id: day,
                    value: entry.value / normDenominator,
                    recordCount: entry.count
                )
            }
            return HeatmapCell(id: day, value: 0, recordCount: 0)
        }

        // Build trend (use raw values, not normalised, for the line chart).
        trendData = allDays.compactMap { day -> TrendPoint? in
            guard let entry = dailyValues[day] else { return TrendPoint(id: day, value: 0) }
            return TrendPoint(id: day, value: entry.value)
        }

        // Build 7-day cycle (average value per weekday).
        var weekdayTotals: [Int: (sum: Double, count: Int)] = [:]  // weekday (1=Sun) -> totals
        for (day, entry) in dailyValues {
            let weekday = cal.component(.weekday, from: day)
            let existing = weekdayTotals[weekday] ?? (sum: 0, count: 0)
            weekdayTotals[weekday] = (sum: existing.sum + entry.value, count: existing.count + 1)
        }

        let maxCycleValue = weekdayTotals.values.map { $0.count > 0 ? $0.sum / Double($0.count) : 0 }.max() ?? 1.0
        let cycleDenominator = maxCycleValue > 0 ? maxCycleValue : 1.0

        // Order: Monday(2) through Sunday(1) – map to indices 0-6.
        let weekdayOrder: [Int] = [2, 3, 4, 5, 6, 7, 1]
        cycleData = weekdayOrder.map { weekday in
            // Use a stable date for `id`: use the weekday offset from a fixed epoch.
            let stableDate = Date(timeIntervalSinceReferenceDate: Double(weekday) * 86400)
            if let totals = weekdayTotals[weekday], totals.count > 0 {
                let avg = totals.sum / Double(totals.count)
                return HeatmapCell(id: stableDate, value: avg / cycleDenominator, recordCount: totals.count)
            }
            return HeatmapCell(id: stableDate, value: 0, recordCount: 0)
        }

        // Build summary stats.
        let activeDays = dailyValues.filter { $0.value.count > 0 }
        let peakEntry = activeDays.max(by: { $0.value.value < $1.value.value })
        let avgValue = activeDays.isEmpty ? 0 : activeDays.values.map(\.value).reduce(0, +) / Double(activeDays.count)
        let streak = computeStreak(activeDays: Set(activeDays.keys))

        summary = SummaryStats(
            peakDate: peakEntry?.key,
            peakValue: peakEntry?.value.value ?? 0,
            averageValue: avgValue,
            currentStreak: streak,
            totalDays: activeDays.count
        )
    }

    /// Computes the current consecutive-day streak ending on today.
    private func computeStreak(activeDays: Set<Date>) -> Int {
        let cal = Calendar.current
        var streak = 0
        var cursor = cal.startOfDay(for: Date())

        while activeDays.contains(cursor) {
            streak += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return streak
    }

    /// Enumerates every calendar day from `start` to `end` inclusive.
    private func enumerateDays(from start: Date, to end: Date) -> [Date] {
        var days: [Date] = []
        var cursor = Calendar.current.startOfDay(for: start)
        let endDay = Calendar.current.startOfDay(for: end)

        while cursor <= endDay {
            days.append(cursor)
            guard let next = Calendar.current.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return days
    }
}
