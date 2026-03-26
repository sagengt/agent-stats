import Foundation

/// Central refresh coordinator — the **only** writer to `UsageResultStore`
/// and `UsageHistoryStoreProtocol`.
///
/// Deduplication logic:
/// - If a refresh is already in flight when `requestRefresh()` is called,
///   a `pendingRefresh` flag is set so that exactly one additional refresh
///   runs as soon as the current one completes.
/// - This prevents unbounded queuing while ensuring the most recent request
///   is always serviced.
actor RefreshOrchestrator {

    // MARK: - Dependencies

    private let registry: ProviderRegistry
    private let resultStore: UsageResultStore
    private let historyStore: any UsageHistoryStoreProtocol

    // MARK: - State

    private var isRefreshing = false
    private var pendingRefresh = false
    private var refreshTask: Task<Void, Never>?
    private var autoRefreshTask: Task<Void, Never>?

    // MARK: - Init

    init(
        registry: ProviderRegistry,
        resultStore: UsageResultStore,
        historyStore: any UsageHistoryStoreProtocol
    ) {
        self.registry = registry
        self.resultStore = resultStore
        self.historyStore = historyStore
    }

    // MARK: - Public API

    /// Requests a refresh.
    ///
    /// If a refresh is already running the request is debounced: one additional
    /// refresh will execute immediately after the current one completes.
    func requestRefresh() async {
        guard !isRefreshing else {
            pendingRefresh = true
            return
        }
        await startRefresh()
    }

    /// Starts a repeating background refresh on `interval` seconds.
    /// Any previous auto-refresh timer is cancelled first.
    func startAutoRefresh(interval: TimeInterval) async {
        await stopAutoRefresh()
        autoRefreshTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.requestRefresh()
                do {
                    try await Task.sleep(for: .seconds(interval))
                } catch {
                    break
                }
            }
        }
    }

    /// Cancels the auto-refresh timer.
    func stopAutoRefresh() async {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }

    // MARK: - Private — refresh lifecycle

    private func startRefresh() async {
        isRefreshing = true
        pendingRefresh = false

        refreshTask = Task { [weak self] in
            guard let self else { return }
            await self.performRefresh()
            await self.didFinishRefresh()
        }
    }

    private func didFinishRefresh() async {
        isRefreshing = false
        if pendingRefresh {
            pendingRefresh = false
            await startRefresh()
        }
    }

    // MARK: - Private — fetch

    /// Fetches from all configured providers in parallel using a `TaskGroup`.
    ///
    /// A single provider failure is captured and surfaced as an `.unavailable`
    /// display data entry so the rest of the results are unaffected.
    private func performRefresh() async {
        let providers = registry.allProviders()
        guard !providers.isEmpty else { return }

        var collectedResults: [ServiceUsageResult] = []

        await withTaskGroup(of: ServiceUsageResult?.self) { group in
            for provider in providers {
                group.addTask {
                    await Self.fetchResult(from: provider)
                }
            }
            for await result in group {
                if let result {
                    collectedResults.append(result)
                }
            }
        }

        guard !collectedResults.isEmpty else { return }

        await resultStore.update(results: collectedResults)
        await historyStore.record(results: collectedResults)
    }

    /// Calls the provider's capability-specific fetch method and returns a `ServiceUsageResult`.
    /// On error, returns a result whose display data is `.unavailable`.
    private static func fetchResult(
        from provider: any UsageProviderProtocol
    ) async -> ServiceUsageResult? {
        guard await provider.isConfigured() else { return nil }

        do {
            var displayData: [UsageDisplayData] = []

            if let quotaProvider = provider as? any QuotaWindowProvider {
                let windows = try await quotaProvider.fetchQuotaWindows()
                displayData.append(contentsOf: windows.map { .quota($0) })
            }
            if let tokenProvider = provider as? any TokenUsageProvider {
                let summary = try await tokenProvider.fetchTokenUsage()
                displayData.append(.tokenSummary(summary))
            }
            if let activityProvider = provider as? any SessionActivityProvider {
                let activity = try await activityProvider.fetchSessionActivity()
                displayData.append(.activity(activity))
            }

            if displayData.isEmpty {
                displayData.append(.unavailable(reason: "No data available"))
            }

            return ServiceUsageResult(
                serviceType: provider.serviceType,
                displayData: displayData,
                fetchedAt: Date()
            )
        } catch {
            let serviceType = provider.serviceType
            let errorMessage = error.localizedDescription
            return ServiceUsageResult(
                serviceType: serviceType,
                displayData: [.unavailable(reason: errorMessage)],
                fetchedAt: Date()
            )
        }
    }
}
