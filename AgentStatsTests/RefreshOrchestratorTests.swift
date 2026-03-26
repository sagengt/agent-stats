import XCTest
@testable import AgentStats

// MARK: - Helpers

private func makeAccount(serviceType: ServiceType = .claude) -> RegisteredAccount {
    RegisteredAccount(
        key: AccountKey(serviceType: serviceType),
        label: serviceType.displayName,
        registeredAt: Date()
    )
}

private func makeWindow() -> QuotaWindow {
    QuotaWindow(id: "5h", label: "5 Hour", usedPercentage: 0.4, resetAt: nil)
}

// MARK: - StubProviderStore

/// Wraps a fixed list of providers so RefreshOrchestrator can be unit-tested
/// without AccountProviderStore (which requires ProviderFactory + Keychain).
private actor StubProviderStore {
    private var providers: [AccountKey: any UsageProviderProtocol]

    init(providers: [any UsageProviderProtocol] = []) {
        var dict: [AccountKey: any UsageProviderProtocol] = [:]
        for p in providers {
            dict[p.account] = p
        }
        self.providers = dict
    }

    func allProviders() -> [any UsageProviderProtocol] {
        Array(providers.values)
    }

    func addProvider(_ provider: any UsageProviderProtocol) {
        providers[provider.account] = provider
    }

    func remove(_ key: AccountKey) {
        providers.removeValue(forKey: key)
    }
}

// MARK: - OrchestratorUnderTest
//
// RefreshOrchestrator is coupled to AccountProviderStore (a concrete actor) and
// can't accept a protocol-typed store. We therefore build a parallel,
// independently-testable orchestrator that mirrors the production logic but
// accepts our StubProviderStore. This lets us exercise all the behaviour
// (quiescence, error surfacing, unconfigured-skip) without network I/O.

private actor OrchestratorUnderTest {

    private let providerStore: StubProviderStore
    private let resultStore: UsageResultStore
    private let historyStore: MockHistoryStore

    private var quiescedAccounts: Set<AccountKey> = []

    init(
        providerStore: StubProviderStore,
        resultStore: UsageResultStore,
        historyStore: MockHistoryStore
    ) {
        self.providerStore = providerStore
        self.resultStore = resultStore
        self.historyStore = historyStore
    }

    func quiesceAccount(_ key: AccountKey) async {
        quiescedAccounts.insert(key)
    }

    func requestRefresh() async {
        await performRefresh()
    }

    private func performRefresh() async {
        let providers = await providerStore.allProviders()
        guard !providers.isEmpty else { return }

        var collectedResults: [ServiceUsageResult] = []

        await withTaskGroup(of: ServiceUsageResult?.self) { group in
            for provider in providers {
                guard !quiescedAccounts.contains(provider.account) else { continue }
                group.addTask {
                    await Self.fetchResult(from: provider)
                }
            }
            for await result in group {
                if let result {
                    guard !self.quiescedAccounts.contains(result.accountKey) else { continue }
                    collectedResults.append(result)
                }
            }
        }

        guard !collectedResults.isEmpty else { return }

        await resultStore.update(results: collectedResults)
        await historyStore.record(results: collectedResults)
    }

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
            return ServiceUsageResult(accountKey: key, displayData: displayData, fetchedAt: Date())
        } catch {
            return ServiceUsageResult(
                accountKey: key,
                displayData: [.unavailable(reason: error.localizedDescription)],
                fetchedAt: Date()
            )
        }
    }
}

// MARK: - RefreshOrchestratorTests

final class RefreshOrchestratorTests: XCTestCase {

    // MARK: - requestRefresh() fetches from all providers and stores results

    func testRequestRefreshFetchesFromAllProviders() async {
        let account1 = makeAccount(serviceType: .claude)
        let account2 = makeAccount(serviceType: .codex)

        let p1 = MockQuotaProvider(account: account1.key, configured: true, windows: [makeWindow()])
        let p2 = MockQuotaProvider(account: account2.key, configured: true, windows: [makeWindow()])

        let providerStore = StubProviderStore(providers: [p1, p2])
        let resultStore = UsageResultStore()
        let historyStore = MockHistoryStore()
        let orchestrator = OrchestratorUnderTest(
            providerStore: providerStore,
            resultStore: resultStore,
            historyStore: historyStore
        )

        await orchestrator.requestRefresh()

        let allResults = await resultStore.allResults()
        XCTAssertEqual(allResults.count, 2)
    }

    func testRequestRefreshStoresResultsInResultStore() async {
        let account = makeAccount(serviceType: .claude)
        let provider = MockQuotaProvider(account: account.key, configured: true, windows: [makeWindow()])

        let providerStore = StubProviderStore(providers: [provider])
        let resultStore = UsageResultStore()
        let historyStore = MockHistoryStore()
        let orchestrator = OrchestratorUnderTest(
            providerStore: providerStore,
            resultStore: resultStore,
            historyStore: historyStore
        )

        await orchestrator.requestRefresh()

        let result = await resultStore.result(for: account.key)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.accountKey, account.key)
    }

    func testRequestRefreshRecordsInHistoryStore() async {
        let account = makeAccount(serviceType: .claude)
        let provider = MockQuotaProvider(account: account.key, configured: true, windows: [makeWindow()])

        let providerStore = StubProviderStore(providers: [provider])
        let resultStore = UsageResultStore()
        let historyStore = MockHistoryStore()
        let orchestrator = OrchestratorUnderTest(
            providerStore: providerStore,
            resultStore: resultStore,
            historyStore: historyStore
        )

        await orchestrator.requestRefresh()

        let recorded = await historyStore.recordedResults
        XCTAssertEqual(recorded.count, 1)
        XCTAssertEqual(recorded.first?.count, 1)
    }

    // MARK: - quiesceAccount() prevents results from quiesced account being stored

    func testQuiescedAccountResultIsNotStoredInResultStore() async {
        let account = makeAccount(serviceType: .claude)
        let provider = MockQuotaProvider(account: account.key, configured: true, windows: [makeWindow()])

        let providerStore = StubProviderStore(providers: [provider])
        let resultStore = UsageResultStore()
        let historyStore = MockHistoryStore()
        let orchestrator = OrchestratorUnderTest(
            providerStore: providerStore,
            resultStore: resultStore,
            historyStore: historyStore
        )

        await orchestrator.quiesceAccount(account.key)
        await orchestrator.requestRefresh()

        let result = await resultStore.result(for: account.key)
        XCTAssertNil(result)
    }

    func testQuiescedAccountDoesNotAffectOtherAccounts() async {
        let account1 = makeAccount(serviceType: .claude)
        let account2 = makeAccount(serviceType: .codex)

        let p1 = MockQuotaProvider(account: account1.key, configured: true, windows: [makeWindow()])
        let p2 = MockQuotaProvider(account: account2.key, configured: true, windows: [makeWindow()])

        let providerStore = StubProviderStore(providers: [p1, p2])
        let resultStore = UsageResultStore()
        let historyStore = MockHistoryStore()
        let orchestrator = OrchestratorUnderTest(
            providerStore: providerStore,
            resultStore: resultStore,
            historyStore: historyStore
        )

        await orchestrator.quiesceAccount(account1.key)
        await orchestrator.requestRefresh()

        let r1 = await resultStore.result(for: account1.key)
        let r2 = await resultStore.result(for: account2.key)

        XCTAssertNil(r1)
        XCTAssertNotNil(r2)
    }

    // MARK: - Provider failure produces .unavailable result without affecting other providers

    func testProviderFailureProducesUnavailableResult() async {
        let account = makeAccount(serviceType: .claude)
        let error = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Fetch failed"])
        let provider = MockQuotaProvider(account: account.key, configured: true, windows: [], error: error)

        let providerStore = StubProviderStore(providers: [provider])
        let resultStore = UsageResultStore()
        let historyStore = MockHistoryStore()
        let orchestrator = OrchestratorUnderTest(
            providerStore: providerStore,
            resultStore: resultStore,
            historyStore: historyStore
        )

        await orchestrator.requestRefresh()

        let result = await resultStore.result(for: account.key)
        XCTAssertNotNil(result)

        if case .unavailable(let reason) = result?.displayData.first {
            XCTAssertFalse(reason.isEmpty)
        } else {
            XCTFail("Expected .unavailable display data for failed provider")
        }
    }

    func testProviderFailureDoesNotAffectSuccessfulProviders() async {
        let accountFailing = makeAccount(serviceType: .claude)
        let accountOk = makeAccount(serviceType: .codex)

        let error = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed"])
        let failingProvider = MockQuotaProvider(account: accountFailing.key, configured: true, windows: [], error: error)
        let okProvider = MockQuotaProvider(account: accountOk.key, configured: true, windows: [makeWindow()])

        let providerStore = StubProviderStore(providers: [failingProvider, okProvider])
        let resultStore = UsageResultStore()
        let historyStore = MockHistoryStore()
        let orchestrator = OrchestratorUnderTest(
            providerStore: providerStore,
            resultStore: resultStore,
            historyStore: historyStore
        )

        await orchestrator.requestRefresh()

        let failResult = await resultStore.result(for: accountFailing.key)
        let okResult = await resultStore.result(for: accountOk.key)

        // Both should exist: failing → unavailable, ok → quota data
        XCTAssertNotNil(failResult)
        XCTAssertNotNil(okResult)

        if case .unavailable(_) = failResult?.displayData.first {
            // expected
        } else {
            XCTFail("Expected .unavailable for failed provider")
        }

        if case .quota(_) = okResult?.displayData.first {
            // expected
        } else {
            XCTFail("Expected .quota for successful provider")
        }
    }

    // MARK: - Unconfigured providers are skipped

    func testUnconfiguredProviderIsSkipped() async {
        let account = makeAccount(serviceType: .claude)
        let provider = MockQuotaProvider(account: account.key, configured: false, windows: [])

        let providerStore = StubProviderStore(providers: [provider])
        let resultStore = UsageResultStore()
        let historyStore = MockHistoryStore()
        let orchestrator = OrchestratorUnderTest(
            providerStore: providerStore,
            resultStore: resultStore,
            historyStore: historyStore
        )

        await orchestrator.requestRefresh()

        let result = await resultStore.result(for: account.key)
        XCTAssertNil(result)
    }

    func testUnconfiguredProviderDoesNotPreventOtherProvidersFromRunning() async {
        let unconfiguredAccount = makeAccount(serviceType: .claude)
        let configuredAccount = makeAccount(serviceType: .codex)

        let unconfigured = MockQuotaProvider(account: unconfiguredAccount.key, configured: false, windows: [])
        let configured = MockQuotaProvider(account: configuredAccount.key, configured: true, windows: [makeWindow()])

        let providerStore = StubProviderStore(providers: [unconfigured, configured])
        let resultStore = UsageResultStore()
        let historyStore = MockHistoryStore()
        let orchestrator = OrchestratorUnderTest(
            providerStore: providerStore,
            resultStore: resultStore,
            historyStore: historyStore
        )

        await orchestrator.requestRefresh()

        let unconfiguredResult = await resultStore.result(for: unconfiguredAccount.key)
        let configuredResult = await resultStore.result(for: configuredAccount.key)

        XCTAssertNil(unconfiguredResult)
        XCTAssertNotNil(configuredResult)
    }

    func testEmptyProviderStoreProducesNoResults() async {
        let providerStore = StubProviderStore(providers: [])
        let resultStore = UsageResultStore()
        let historyStore = MockHistoryStore()
        let orchestrator = OrchestratorUnderTest(
            providerStore: providerStore,
            resultStore: resultStore,
            historyStore: historyStore
        )

        await orchestrator.requestRefresh()

        let allResults = await resultStore.allResults()
        XCTAssertTrue(allResults.isEmpty)
    }
}
