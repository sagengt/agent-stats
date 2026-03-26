import XCTest
@testable import AgentStats

// MARK: - IntegrationMockHistoryStore

/// In-memory `UsageHistoryStoreProtocol` that captures every batch passed to
/// `record(results:)` so tests can assert on the recorded contents.
actor IntegrationMockHistoryStore: UsageHistoryStoreProtocol {

    private(set) var recordedResults: [ServiceUsageResult] = []

    func record(results: [ServiceUsageResult]) async {
        recordedResults.append(contentsOf: results)
    }

    func records(
        for service: ServiceType,
        accountKey: AccountKey?,
        since: Date,
        until: Date
    ) async -> [UsageHistoryRecord] { [] }

    func availableServices() async -> [ServiceType] {
        Array(Set(recordedResults.map(\.serviceType)))
    }
}

// MARK: - ConfiguredMockQuotaProvider

/// A `QuotaWindowProvider` stub that is always configured and returns a
/// pre-set `QuotaWindow`.  Used to drive the orchestrator without real network
/// calls.
struct ConfiguredMockQuotaProvider: QuotaWindowProvider {
    let account: AccountKey
    var serviceType: ServiceType { account.serviceType }
    let window: QuotaWindow

    func isConfigured() async -> Bool { true }
    func fetchQuotaWindows() async throws -> [QuotaWindow] { [window] }
}

// MARK: - ProviderStoreProtocol

/// Seam that lets `TestRefreshOrchestrator` accept either a real
/// `AccountProviderStore` or a test double.
protocol ProviderStoreProtocol: AnyObject, Sendable {
    func allProviders() async -> [any UsageProviderProtocol]
    func provider(for key: AccountKey) async -> (any UsageProviderProtocol)?
    func remove(_ key: AccountKey) async
}

extension AccountProviderStore: ProviderStoreProtocol {}

// MARK: - MockProviderStore

/// Test double for `AccountProviderStore` that accepts pre-built providers
/// directly, bypassing `ProviderFactory`.
actor MockProviderStore: ProviderStoreProtocol {
    private var providers: [AccountKey: any UsageProviderProtocol]

    init(providers: [any UsageProviderProtocol]) {
        self.providers = Dictionary(uniqueKeysWithValues: providers.map { ($0.account, $0) })
    }

    func allProviders() async -> [any UsageProviderProtocol] { Array(providers.values) }

    func provider(for key: AccountKey) async -> (any UsageProviderProtocol)? { providers[key] }

    func remove(_ key: AccountKey) async { providers.removeValue(forKey: key) }
}

// MARK: - TestRefreshOrchestrator

/// Mirrors the core logic of `RefreshOrchestrator` but accepts any
/// `ProviderStoreProtocol`, enabling injection of `MockProviderStore` in tests.
actor TestRefreshOrchestrator {

    private let providerStore: any ProviderStoreProtocol
    private let resultStore: UsageResultStore
    private let historyStore: any UsageHistoryStoreProtocol
    private var quiescedAccounts: Set<AccountKey> = []

    init(
        providerStore: any ProviderStoreProtocol,
        resultStore: UsageResultStore,
        historyStore: any UsageHistoryStoreProtocol
    ) {
        self.providerStore = providerStore
        self.resultStore   = resultStore
        self.historyStore  = historyStore
    }

    func quiesceAccount(_ key: AccountKey) {
        quiescedAccounts.insert(key)
    }

    func requestRefresh() async {
        await performRefresh()
    }

    private func performRefresh() async {
        let providers = await providerStore.allProviders()
        guard !providers.isEmpty else { return }

        var collected: [ServiceUsageResult] = []

        await withTaskGroup(of: ServiceUsageResult?.self) { group in
            for provider in providers {
                guard !quiescedAccounts.contains(provider.account) else { continue }
                group.addTask { await Self.fetchResult(from: provider) }
            }
            for await result in group {
                if let result, !self.quiescedAccounts.contains(result.accountKey) {
                    collected.append(result)
                }
            }
        }

        guard !collected.isEmpty else { return }
        await resultStore.update(results: collected)
        await historyStore.record(results: collected)
    }

    private static func fetchResult(
        from provider: any UsageProviderProtocol
    ) async -> ServiceUsageResult? {
        guard await provider.isConfigured() else { return nil }
        let key = provider.account
        do {
            var displayData: [UsageDisplayData] = []
            if let qp = provider as? any QuotaWindowProvider {
                let windows = try await qp.fetchQuotaWindows()
                displayData.append(contentsOf: windows.map { .quota($0) })
            }
            if displayData.isEmpty { displayData.append(.unavailable(reason: "No data")) }
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

// MARK: - MultiAccountIntegrationTests

final class MultiAccountIntegrationTests: XCTestCase {

    // MARK: - Helpers

    private func makeKey(_ serviceType: ServiceType, id: String? = nil) -> AccountKey {
        AccountKey(serviceType: serviceType, accountId: id ?? UUID().uuidString)
    }

    private func makeWindow(id: String = "5h", usage: Double = 0.5) -> QuotaWindow {
        QuotaWindow(id: id, label: "Test Window", usedPercentage: usage, resetAt: nil)
    }

    private func makeOrchestrator(
        providers: [any UsageProviderProtocol],
        resultStore: UsageResultStore,
        historyStore: IntegrationMockHistoryStore
    ) -> (TestRefreshOrchestrator, MockProviderStore) {
        let providerStore = MockProviderStore(providers: providers)
        let orchestrator  = TestRefreshOrchestrator(
            providerStore: providerStore,
            resultStore: resultStore,
            historyStore: historyStore
        )
        return (orchestrator, providerStore)
    }

    // MARK: - Full Multi-Account Data Flow

    func testRefreshPopulatesResultStoreWithAllThreeAccounts() async {
        let claudeKey1 = makeKey(.claude, id: "claude-1")
        let claudeKey2 = makeKey(.claude, id: "claude-2")
        let codexKey   = makeKey(.codex,  id: "codex-1")

        let resultStore  = UsageResultStore()
        let historyStore = IntegrationMockHistoryStore()
        let (orchestrator, _) = makeOrchestrator(
            providers: [
                ConfiguredMockQuotaProvider(account: claudeKey1, window: makeWindow()),
                ConfiguredMockQuotaProvider(account: claudeKey2, window: makeWindow()),
                ConfiguredMockQuotaProvider(account: codexKey,   window: makeWindow()),
            ],
            resultStore: resultStore,
            historyStore: historyStore
        )

        await orchestrator.requestRefresh()

        let results = await resultStore.allResults()
        XCTAssertEqual(results.count, 3)

        let keys = Set(results.map(\.accountKey))
        XCTAssertTrue(keys.contains(claudeKey1))
        XCTAssertTrue(keys.contains(claudeKey2))
        XCTAssertTrue(keys.contains(codexKey))
    }

    func testResultsForSameServiceTypeAreDistinguishableByAccountKey() async {
        let claudeKey1 = makeKey(.claude, id: "dist-claude-1")
        let claudeKey2 = makeKey(.claude, id: "dist-claude-2")

        let resultStore  = UsageResultStore()
        let (orchestrator, _) = makeOrchestrator(
            providers: [
                ConfiguredMockQuotaProvider(account: claudeKey1, window: makeWindow(usage: 0.1)),
                ConfiguredMockQuotaProvider(account: claudeKey2, window: makeWindow(usage: 0.9)),
            ],
            resultStore: resultStore,
            historyStore: IntegrationMockHistoryStore()
        )

        await orchestrator.requestRefresh()

        let r1 = await resultStore.result(for: claudeKey1)
        let r2 = await resultStore.result(for: claudeKey2)

        XCTAssertNotNil(r1)
        XCTAssertNotNil(r2)
        XCTAssertEqual(r1?.accountKey, claudeKey1)
        XCTAssertEqual(r2?.accountKey, claudeKey2)
    }

    func testHistoryStoreRecordsAllThreeResults() async {
        let keys: [AccountKey] = [
            makeKey(.claude, id: "hist-1"),
            makeKey(.claude, id: "hist-2"),
            makeKey(.codex,  id: "hist-3"),
        ]

        let resultStore  = UsageResultStore()
        let historyStore = IntegrationMockHistoryStore()
        let (orchestrator, _) = makeOrchestrator(
            providers: keys.map { ConfiguredMockQuotaProvider(account: $0, window: makeWindow()) },
            resultStore: resultStore,
            historyStore: historyStore
        )

        await orchestrator.requestRefresh()

        let recorded = await historyStore.recordedResults
        XCTAssertEqual(recorded.count, 3)

        let recordedKeys = Set(recorded.map(\.accountKey))
        for key in keys {
            XCTAssertTrue(recordedKeys.contains(key), "Missing key \(key.accountId) in history")
        }
    }

    // MARK: - Deletion Flow

    func testDeletionReducesResultCountToTwo() async {
        let claudeKey1 = makeKey(.claude, id: "del-claude-1")
        let claudeKey2 = makeKey(.claude, id: "del-claude-2")
        let codexKey   = makeKey(.codex,  id: "del-codex-1")

        let resultStore  = UsageResultStore()
        let historyStore = IntegrationMockHistoryStore()
        let (orchestrator, providerStore) = makeOrchestrator(
            providers: [
                ConfiguredMockQuotaProvider(account: claudeKey1, window: makeWindow()),
                ConfiguredMockQuotaProvider(account: claudeKey2, window: makeWindow()),
                ConfiguredMockQuotaProvider(account: codexKey,   window: makeWindow()),
            ],
            resultStore: resultStore,
            historyStore: historyStore
        )

        // Initial refresh — 3 accounts
        await orchestrator.requestRefresh()
        let initial = await resultStore.allResults()
        XCTAssertEqual(initial.count, 3, "Pre-condition: expected 3 results")

        // Delete claudeKey1: quiesce → remove from provider store → remove from result store
        await orchestrator.quiesceAccount(claudeKey1)
        await providerStore.remove(claudeKey1)
        await resultStore.remove(account: claudeKey1)

        // Second refresh — only 2 providers remain
        await orchestrator.requestRefresh()

        let final = await resultStore.allResults()
        XCTAssertEqual(final.count, 2)
        XCTAssertFalse(final.contains(where: { $0.accountKey == claudeKey1 }),
                       "Deleted account must not appear in results")
        XCTAssertTrue(final.contains(where: { $0.accountKey == claudeKey2 }))
        XCTAssertTrue(final.contains(where: { $0.accountKey == codexKey }))
    }

    func testQuiescedAccountIsNotWrittenToResultStoreAfterDeletion() async {
        let claudeKey = makeKey(.claude, id: "qsc-claude")
        let codexKey  = makeKey(.codex,  id: "qsc-codex")

        let resultStore  = UsageResultStore()
        let (orchestrator, providerStore) = makeOrchestrator(
            providers: [
                ConfiguredMockQuotaProvider(account: claudeKey, window: makeWindow()),
                ConfiguredMockQuotaProvider(account: codexKey,  window: makeWindow()),
            ],
            resultStore: resultStore,
            historyStore: IntegrationMockHistoryStore()
        )

        // Populate both accounts
        await orchestrator.requestRefresh()

        // Quiesce + remove + clean
        await orchestrator.quiesceAccount(claudeKey)
        await providerStore.remove(claudeKey)
        await resultStore.remove(account: claudeKey)

        // Second refresh
        await orchestrator.requestRefresh()

        let results = await resultStore.allResults()
        XCTAssertFalse(results.contains(where: { $0.accountKey == claudeKey }),
                       "Quiesced account must not reappear in result store")
        XCTAssertTrue(results.contains(where: { $0.accountKey == codexKey }))
    }
}
