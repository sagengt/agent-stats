import SwiftUI
import Combine

// MARK: - UsageViewModel

/// Drives the menu bar UI by subscribing to live usage results from
/// `UsageResultStore` and delegating refresh requests to `RefreshOrchestrator`.
///
/// This object performs **no I/O**. It is a pure projection of the actor-based
/// infrastructure layer onto `@Published` SwiftUI state.
@MainActor
final class UsageViewModel: ObservableObject {

    // MARK: Published state

    /// All account results currently available, ordered by service priority then account registration order.
    @Published var results: [ServiceUsageResult] = []

    /// `true` while a refresh is in progress.
    @Published var isRefreshing: Bool = false

    /// Wall-clock time of the most recent successful fetch.
    @Published var lastRefreshedAt: Date?

    // MARK: Dependencies

    private let resultStore: UsageResultStore
    private let orchestrator: RefreshOrchestrator
    let accountManager: AccountManager

    // MARK: Internal

    /// Holds the long-running observation task so it can be cancelled on deinit.
    private var streamTask: Task<Void, Never>?

    // MARK: Init

    init(
        resultStore: UsageResultStore,
        orchestrator: RefreshOrchestrator,
        accountManager: AccountManager
    ) {
        self.resultStore = resultStore
        self.orchestrator = orchestrator
        self.accountManager = accountManager
        startObserving()
        refreshLabels()
    }

    deinit {
        streamTask?.cancel()
    }

    // MARK: Public API

    /// Requests an immediate refresh of all configured providers.
    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task {
            await orchestrator.requestRefresh()
            self.isRefreshing = false
        }
    }

    // MARK: Computed helpers for UI

    /// Results grouped by `ServiceType`, preserving canonical service ordering.
    ///
    /// Each entry contains all accounts for a given service so the UI can
    /// decide whether to show account labels (when `count > 1`).
    var resultsByService: [(serviceType: ServiceType, results: [ServiceUsageResult])] {
        var grouped: [ServiceType: [ServiceUsageResult]] = [:]
        for result in results {
            grouped[result.serviceType, default: []].append(result)
        }
        return ServiceType.allCases.compactMap { service in
            guard let serviceResults = grouped[service], !serviceResults.isEmpty else { return nil }
            return (serviceType: service, results: serviceResults)
        }
    }

    /// Returns the human-readable label for the account identified by `key`.
    ///
    /// Looks up the label synchronously from the cached results by matching
    /// Cached account labels, refreshed alongside results.
    @Published var accountLabels: [AccountKey: String] = [:]

    /// Returns the label for `key`, using the cached value or falling back to service name.
    func label(for key: AccountKey) -> String {
        accountLabels[key] ?? key.serviceType.displayName
    }

    /// Reloads labels from AccountManager into the cache.
    private func refreshLabels() {
        Task {
            let accounts = await accountManager.allAccounts()
            var labels: [AccountKey: String] = [:]
            for account in accounts {
                let label = account.label.trimmingCharacters(in: .whitespacesAndNewlines)
                if !label.isEmpty {
                    labels[account.key] = label
                }
            }
            self.accountLabels = labels
        }
    }

    /// Results whose display data contains at least one `.quota` entry.
    var quotaResults: [ServiceUsageResult] {
        results.filter { result in
            result.displayData.contains { if case .quota = $0 { return true } else { return false } }
        }
    }

    /// Results whose display data contains at least one `.tokenSummary` entry.
    var tokenResults: [ServiceUsageResult] {
        results.filter { result in
            result.displayData.contains { if case .tokenSummary = $0 { return true } else { return false } }
        }
    }

    /// Results whose display data contains at least one `.activity` entry.
    var activityResults: [ServiceUsageResult] {
        results.filter { result in
            result.displayData.contains { if case .activity = $0 { return true } else { return false } }
        }
    }

    /// The highest quota usage percentage across all quota-type results.
    /// Returns `nil` when there are no quota results.
    var highestQuotaPercentage: Double? {
        let percentages = quotaResults.flatMap { result in
            result.displayData.compactMap { item -> Double? in
                if case .quota(let window) = item { return window.usedPercentage }
                return nil
            }
        }
        return percentages.max()
    }

    /// Formatted string describing how long ago the last refresh occurred.
    var lastRefreshedDescription: String {
        guard let date = lastRefreshedAt else { return "Never" }
        let interval = -date.timeIntervalSinceNow
        switch interval {
        case ..<60:
            return "Just now"
        case 60..<3600:
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        default:
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        }
    }

    // MARK: Private

    private func startObserving() {
        streamTask = Task { [weak self] in
            guard let self else { return }
            for await updatedResults in await self.resultStore.resultStream() {
                guard !Task.isCancelled else { return }
                AppLogger.log("[ViewModel] Received \(updatedResults.count) result(s)")
                self.results = updatedResults
                self.refreshLabels()
                if let newest = updatedResults.map(\.fetchedAt).max() {
                    self.lastRefreshedAt = newest
                }
            }
        }
    }
}
