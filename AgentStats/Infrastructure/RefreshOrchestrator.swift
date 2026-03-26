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
///
/// Quiescence:
/// - `quiesceAccount(_:)` marks an `AccountKey` so that any result produced
///   for that key by an in-flight fetch is silently discarded, and the key is
///   excluded from subsequent refresh cycles.
/// - `AccountManager` calls this before removing the provider and cleaning up
///   credentials, ensuring no stale write occurs after account deletion.
actor RefreshOrchestrator {

    // MARK: - Dependencies

    private let providerStore: AccountProviderStore
    private let resultStore: UsageResultStore
    private let historyStore: any UsageHistoryStoreProtocol

    // MARK: - State

    private var isRefreshing = false
    private var pendingRefresh = false
    private var refreshTask: Task<Void, Never>?
    private var autoRefreshTask: Task<Void, Never>?

    /// Keys for accounts that are being torn down.
    ///
    /// Results produced for these accounts during an in-flight refresh are
    /// rejected so that deleted accounts never appear in the result store.
    private var quiescedAccounts: Set<AccountKey> = []

    // MARK: - Init

    init(
        providerStore: AccountProviderStore,
        resultStore: UsageResultStore,
        historyStore: any UsageHistoryStoreProtocol
    ) {
        self.providerStore = providerStore
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

    /// Marks `key` as quiesced so results for it are discarded in the current
    /// and all future refresh cycles.
    ///
    /// Called by `AccountManager` as the first step of account deletion.
    func quiesceAccount(_ key: AccountKey) async {
        quiescedAccounts.insert(key)
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
    /// Results for quiesced accounts are silently dropped before writing.
    private func performRefresh() async {
        let providers = await providerStore.allProviders()
        guard !providers.isEmpty else { return }

        var collectedResults: [ServiceUsageResult] = []

        await withTaskGroup(of: ServiceUsageResult?.self) { group in
            for provider in providers {
                // Skip providers for accounts that are being deleted.
                guard !quiescedAccounts.contains(provider.account) else { continue }
                group.addTask {
                    await Self.fetchResult(from: provider)
                }
            }
            for await result in group {
                if let result {
                    // Double-check quiescence in case the account was deleted
                    // while this particular fetch was in flight.
                    guard !self.quiescedAccounts.contains(result.accountKey) else { continue }
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

        let key = provider.account

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
                accountKey: key,
                displayData: displayData,
                fetchedAt: Date()
            )
        } catch {
            return ServiceUsageResult(
                accountKey: key,
                displayData: [.unavailable(reason: error.localizedDescription)],
                fetchedAt: Date()
            )
        }
    }
}
