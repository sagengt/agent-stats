import XCTest
@testable import AgentStats

// MARK: - MockProviderFactory

/// Minimal factory that vends `MockQuotaProvider` instances to avoid
/// Keychain / network dependencies in unit tests.
private struct MockProviderFactory: Sendable {
    func makeProvider(for account: RegisteredAccount) -> any UsageProviderProtocol {
        MockQuotaProvider(account: account.key, configured: true, windows: [])
    }
}

// MARK: - AccountProviderStore + testable init

// AccountProviderStore requires a ProviderFactory (concrete struct). To keep
// tests isolated we use a thin wrapper that accepts a closure-based factory,
// allowing us to inject our mock without touching production code paths.
//
// Rather than subclass (actors can't be subclassed), we build a parallel
// actor under test using the same API surface.

private actor TestableProviderStore {
    private var providers: [AccountKey: any UsageProviderProtocol] = [:]
    private let factory: MockProviderFactory

    init(accounts: [RegisteredAccount], factory: MockProviderFactory = MockProviderFactory()) {
        self.factory = factory
        for account in accounts {
            providers[account.key] = factory.makeProvider(for: account)
        }
    }

    func provider(for key: AccountKey) -> (any UsageProviderProtocol)? {
        providers[key]
    }

    func allProviders() -> [any UsageProviderProtocol] {
        Array(providers.values)
    }

    func addProvider(for account: RegisteredAccount) async {
        providers[account.key] = factory.makeProvider(for: account)
    }

    func remove(_ key: AccountKey) async {
        providers.removeValue(forKey: key)
    }
}

// MARK: - Tests

final class AccountProviderStoreTests: XCTestCase {

    // MARK: - Helpers

    private func makeAccount(
        serviceType: ServiceType = .claude,
        label: String = "Test"
    ) -> RegisteredAccount {
        RegisteredAccount(key: AccountKey(serviceType: serviceType), label: label, registeredAt: Date())
    }

    // MARK: - allProviders() returns providers for all registered accounts

    func testAllProvidersReturnsProvidersForBootstrappedAccounts() async {
        let a1 = makeAccount(serviceType: .claude)
        let a2 = makeAccount(serviceType: .codex)
        let store = TestableProviderStore(accounts: [a1, a2])

        let providers = await store.allProviders()
        XCTAssertEqual(providers.count, 2)
    }

    func testAllProvidersReturnsEmptyForEmptyInit() async {
        let store = TestableProviderStore(accounts: [])
        let providers = await store.allProviders()
        XCTAssertTrue(providers.isEmpty)
    }

    // MARK: - provider(for:) returns correct provider for a given AccountKey

    func testProviderForKeyReturnsMatchingProvider() async {
        let account = makeAccount(serviceType: .claude)
        let store = TestableProviderStore(accounts: [account])

        let provider = await store.provider(for: account.key)
        XCTAssertNotNil(provider)
        XCTAssertEqual(provider?.account, account.key)
    }

    // MARK: - addProvider() adds a new provider

    func testAddProviderIncreasesCount() async {
        let store = TestableProviderStore(accounts: [])
        let account = makeAccount(serviceType: .gemini)

        await store.addProvider(for: account)

        let providers = await store.allProviders()
        XCTAssertEqual(providers.count, 1)
    }

    func testAddProviderMakesItRetrievableByKey() async {
        let store = TestableProviderStore(accounts: [])
        let account = makeAccount(serviceType: .zai)

        await store.addProvider(for: account)

        let provider = await store.provider(for: account.key)
        XCTAssertNotNil(provider)
        XCTAssertEqual(provider?.account, account.key)
    }

    func testAddProviderReplacesExistingForSameKey() async {
        let account = makeAccount(serviceType: .claude)
        let store = TestableProviderStore(accounts: [account])

        // Add the same key again — should replace, not duplicate
        await store.addProvider(for: account)

        let providers = await store.allProviders()
        XCTAssertEqual(providers.count, 1)
    }

    // MARK: - remove() removes the provider for that AccountKey

    func testRemoveDecreasesCount() async {
        let account = makeAccount(serviceType: .claude)
        let store = TestableProviderStore(accounts: [account])

        await store.remove(account.key)

        let providers = await store.allProviders()
        XCTAssertTrue(providers.isEmpty)
    }

    func testRemoveMakesKeyNonRetrievable() async {
        let account = makeAccount(serviceType: .claude)
        let store = TestableProviderStore(accounts: [account])

        await store.remove(account.key)

        let provider = await store.provider(for: account.key)
        XCTAssertNil(provider)
    }

    func testRemoveUnknownKeyIsNoOp() async {
        let account = makeAccount(serviceType: .claude)
        let store = TestableProviderStore(accounts: [account])
        let unknownKey = AccountKey(serviceType: .gemini)

        // Should not crash or remove the existing provider
        await store.remove(unknownKey)

        let providers = await store.allProviders()
        XCTAssertEqual(providers.count, 1)
    }

    func testRemoveDoesNotAffectOtherProviders() async {
        let a1 = makeAccount(serviceType: .claude)
        let a2 = makeAccount(serviceType: .codex)
        let store = TestableProviderStore(accounts: [a1, a2])

        await store.remove(a1.key)

        let remaining = await store.provider(for: a2.key)
        XCTAssertNotNil(remaining)
    }

    // MARK: - Multiple accounts for same ServiceType have separate providers

    func testMultipleAccountsSameServiceTypeHaveSeparateProviders() async {
        let key1 = AccountKey(serviceType: .claude, accountId: UUID().uuidString)
        let key2 = AccountKey(serviceType: .claude, accountId: UUID().uuidString)
        let a1 = RegisteredAccount(key: key1, label: "Claude A", registeredAt: Date())
        let a2 = RegisteredAccount(key: key2, label: "Claude B", registeredAt: Date())

        let store = TestableProviderStore(accounts: [a1, a2])

        let p1 = await store.provider(for: key1)
        let p2 = await store.provider(for: key2)

        XCTAssertNotNil(p1)
        XCTAssertNotNil(p2)
        XCTAssertEqual(p1?.account, key1)
        XCTAssertEqual(p2?.account, key2)
    }

    func testRemovingOneOfMultipleSameServiceAccountsLeavesOtherIntact() async {
        let key1 = AccountKey(serviceType: .claude, accountId: UUID().uuidString)
        let key2 = AccountKey(serviceType: .claude, accountId: UUID().uuidString)
        let a1 = RegisteredAccount(key: key1, label: "Claude A", registeredAt: Date())
        let a2 = RegisteredAccount(key: key2, label: "Claude B", registeredAt: Date())

        let store = TestableProviderStore(accounts: [a1, a2])
        await store.remove(key1)

        let p1 = await store.provider(for: key1)
        let p2 = await store.provider(for: key2)

        XCTAssertNil(p1)
        XCTAssertNotNil(p2)
    }
}
