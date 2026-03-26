import XCTest
@testable import AgentStats

/// Verifies that `AccountProviderStore` provides the multi-account functionality
/// that replaces the old single-keyed `ProviderRegistry`.
final class ProviderRegistryCompatTests: XCTestCase {

    // MARK: - Helpers

    private func makeFactory() -> ProviderFactory {
        ProviderFactory(credentialStore: CredentialStore(), apiClient: APIClient())
    }

    private func makeRegisteredAccount(serviceType: ServiceType, label: String = "test") -> RegisteredAccount {
        let key = AccountKey(serviceType: serviceType, accountId: UUID().uuidString)
        return RegisteredAccount(key: key, label: label, registeredAt: Date())
    }

    // MARK: - Canonical registration (1 AccountKey = 1 provider, no duplicates)

    func testSingleAccountRegistersOneProvider() async {
        let account = makeRegisteredAccount(serviceType: .claude)
        let store = AccountProviderStore(accounts: [account], factory: makeFactory())

        let providers = await store.allProviders()

        XCTAssertEqual(providers.count, 1)
    }

    func testDuplicateAccountKeyReplacesExistingProvider() async {
        // Two RegisteredAccounts sharing the same AccountKey
        let sharedKey = AccountKey(serviceType: .claude, accountId: "same-id")
        let account1 = RegisteredAccount(key: sharedKey, label: "first", registeredAt: Date())
        let account2 = RegisteredAccount(key: sharedKey, label: "second", registeredAt: Date())

        let store = AccountProviderStore(accounts: [account1, account2], factory: makeFactory())

        let providers = await store.allProviders()

        // The second registration must have overwritten the first.
        XCTAssertEqual(providers.count, 1)
        XCTAssertEqual(providers.first?.account, sharedKey)
    }

    func testAddProviderReplacesExistingProviderForSameKey() async {
        let account = makeRegisteredAccount(serviceType: .codex)
        let store = AccountProviderStore(accounts: [account], factory: makeFactory())

        // Re-add the same account (simulates re-auth replacing the provider).
        await store.addProvider(for: account)

        let providers = await store.allProviders()
        XCTAssertEqual(providers.count, 1)
        XCTAssertEqual(providers.first?.account, account.key)
    }

    // MARK: - Multiple accounts for same ServiceType

    func testTwoClaudeAccountsAreStoredIndependently() async {
        let claude1 = makeRegisteredAccount(serviceType: .claude, label: "Work")
        let claude2 = makeRegisteredAccount(serviceType: .claude, label: "Personal")
        let store = AccountProviderStore(accounts: [claude1, claude2], factory: makeFactory())

        let providers = await store.allProviders()

        XCTAssertEqual(providers.count, 2)
        let keys = Set(providers.map(\.account))
        XCTAssertTrue(keys.contains(claude1.key))
        XCTAssertTrue(keys.contains(claude2.key))
    }

    func testMixedServiceTypesAreAllRegistered() async {
        let claudeAccount = makeRegisteredAccount(serviceType: .claude)
        let codexAccount  = makeRegisteredAccount(serviceType: .codex)
        let geminiAccount = makeRegisteredAccount(serviceType: .gemini)

        let store = AccountProviderStore(
            accounts: [claudeAccount, codexAccount, geminiAccount],
            factory: makeFactory()
        )

        let providers = await store.allProviders()

        XCTAssertEqual(providers.count, 3)
    }

    func testProviderForKeyReturnsCorrectProvider() async {
        let account = makeRegisteredAccount(serviceType: .claude)
        let store = AccountProviderStore(accounts: [account], factory: makeFactory())

        let provider = await store.provider(for: account.key)

        XCTAssertNotNil(provider)
        XCTAssertEqual(provider?.account, account.key)
    }

    func testProviderForUnknownKeyReturnsNil() async {
        let account = makeRegisteredAccount(serviceType: .claude)
        let store = AccountProviderStore(accounts: [account], factory: makeFactory())

        let unknownKey = AccountKey(serviceType: .claude, accountId: "does-not-exist")
        let provider = await store.provider(for: unknownKey)

        XCTAssertNil(provider)
    }

    // MARK: - provider(for:) returns nil after remove()

    func testProviderForKeyReturnsNilAfterRemove() async {
        let account = makeRegisteredAccount(serviceType: .claude)
        let store = AccountProviderStore(accounts: [account], factory: makeFactory())

        await store.remove(account.key)

        let provider = await store.provider(for: account.key)
        XCTAssertNil(provider)
    }

    func testAllProvidersIsEmptyAfterRemovingLastAccount() async {
        let account = makeRegisteredAccount(serviceType: .codex)
        let store = AccountProviderStore(accounts: [account], factory: makeFactory())

        await store.remove(account.key)

        let providers = await store.allProviders()
        XCTAssertTrue(providers.isEmpty)
    }

    func testRemoveOnlyAffectsTargetedAccount() async {
        let claude1 = makeRegisteredAccount(serviceType: .claude, label: "Work")
        let claude2 = makeRegisteredAccount(serviceType: .claude, label: "Personal")
        let store = AccountProviderStore(accounts: [claude1, claude2], factory: makeFactory())

        await store.remove(claude1.key)

        let remaining = await store.allProviders()
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.account, claude2.key)
    }

    func testRemoveNonExistentKeyIsNoOp() async {
        let account = makeRegisteredAccount(serviceType: .claude)
        let store = AccountProviderStore(accounts: [account], factory: makeFactory())
        let ghostKey = AccountKey(serviceType: .gemini, accountId: "ghost")

        // Should not crash or alter existing providers
        await store.remove(ghostKey)

        let providers = await store.allProviders()
        XCTAssertEqual(providers.count, 1)
    }
}
