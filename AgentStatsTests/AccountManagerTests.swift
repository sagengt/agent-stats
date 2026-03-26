import XCTest
@testable import AgentStats

// MARK: - Test doubles

/// Minimal RefreshOrchestrator stand-in that records which accounts were quiesced.
/// AccountManager calls `orchestrator.quiesceAccount(_:)` during `unregister`.
/// Because `RefreshOrchestrator` is a concrete actor that requires real
/// AccountProviderStore / UsageResultStore / etc., we test AccountManager by
/// constructing the real dependency graph with in-memory stores.

final class AccountManagerTests: XCTestCase {

    // MARK: - Factory

    /// Builds a fully wired AccountManager with an empty snapshot and real
    /// (in-memory) stores. The RefreshOrchestrator is initialised with stubs
    /// so no network I/O occurs.
    private func makeManager() async -> AccountManager {
        let snapshot = AccountSnapshot()

        // ProviderFactory requires a real CredentialStore + APIClient.
        // We create lightweight instances that won't make network calls.
        let credentialStore = CredentialStore()
        let apiClient = APIClient()
        let factory = ProviderFactory(credentialStore: credentialStore, apiClient: apiClient)

        let providerStore = AccountProviderStore(accounts: [], factory: factory)
        let resultStore = UsageResultStore()
        let historyStore = MockHistoryStore()

        let orchestrator = RefreshOrchestrator(
            providerStore: providerStore,
            resultStore: resultStore,
            historyStore: historyStore
        )

        return AccountManager(
            snapshot: snapshot,
            providerStore: providerStore,
            credentialStore: credentialStore,
            resultStore: resultStore,
            orchestrator: orchestrator
        )
    }

    // MARK: - registerProvisional() adds account to provisionalAccounts

    func testRegisterProvisionalAddsToProvisionalAccounts() async {
        let manager = await makeManager()

        let key = await manager.registerProvisional(service: .claude, label: "My Claude")

        // The account should not yet appear in active accounts
        let active = await manager.allAccounts()
        XCTAssertFalse(active.contains { $0.key == key })

        // But the key must be valid (non-nil serviceType matches)
        XCTAssertEqual(key.serviceType, .claude)
    }

    func testRegisterProvisionalReturnsKeyWithCorrectServiceType() async {
        let manager = await makeManager()

        let key = await manager.registerProvisional(service: .codex, label: "Codex")

        XCTAssertEqual(key.serviceType, .codex)
    }

    func testRegisterProvisionalDoesNotAddToActiveAccounts() async {
        let manager = await makeManager()

        _ = await manager.registerProvisional(service: .claude, label: "Provisional")

        let active = await manager.allAccounts()
        XCTAssertTrue(active.isEmpty)
    }

    // MARK: - activateAccount() moves from provisional to active

    func testActivateAccountMovesFromProvisionalToActive() async {
        let manager = await makeManager()

        let key = await manager.registerProvisional(service: .claude, label: "Activate me")
        await manager.activateAccount(key)

        let active = await manager.allAccounts()
        XCTAssertEqual(active.count, 1)
        XCTAssertEqual(active.first?.key, key)
    }

    func testActivateAccountUsesSuppliedLabel() async {
        let manager = await makeManager()

        let key = await manager.registerProvisional(service: .claude, label: "My Label")
        await manager.activateAccount(key)

        let active = await manager.allAccounts()
        XCTAssertEqual(active.first?.label, "My Label")
    }

    func testActivateAccountIsIdempotentForUnknownKey() async {
        let manager = await makeManager()

        let unknownKey = AccountKey(serviceType: .gemini)
        await manager.activateAccount(unknownKey)

        let active = await manager.allAccounts()
        XCTAssertTrue(active.isEmpty)
    }

    func testActivateAccountRemovesFromProvisionalList() async {
        let manager = await makeManager()

        let key = await manager.registerProvisional(service: .claude, label: "Temp")
        await manager.activateAccount(key)

        // Activating twice should not duplicate the account
        await manager.activateAccount(key)

        let active = await manager.allAccounts()
        XCTAssertEqual(active.count, 1)
    }

    // MARK: - discardProvisional() removes from provisional (no tombstone)

    func testDiscardProvisionalRemovesFromProvisional() async {
        let manager = await makeManager()

        let key = await manager.registerProvisional(service: .claude, label: "Discard me")
        await manager.discardProvisional(key)

        // Should not appear in active accounts
        let active = await manager.allAccounts()
        XCTAssertFalse(active.contains { $0.key == key })
    }

    func testDiscardProvisionalDoesNotCreateTombstone() async {
        let manager = await makeManager()

        let key = await manager.registerProvisional(service: .claude, label: "No tombstone")
        await manager.discardProvisional(key)

        let tombstoned = await manager.tombstonedAccounts()
        XCTAssertFalse(tombstoned.contains { $0.key == key })
    }

    func testDiscardProvisionalIsNoOpForActiveAccount() async {
        let manager = await makeManager()

        let key = await manager.registerProvisional(service: .claude, label: "Active one")
        await manager.activateAccount(key)
        await manager.discardProvisional(key)

        // Active account should still be present
        let active = await manager.allAccounts()
        XCTAssertTrue(active.contains { $0.key == key })
    }

    // MARK: - unregister() moves from active to tombstoned

    func testUnregisterRemovesFromActiveAccounts() async {
        let manager = await makeManager()

        let key = await manager.registerProvisional(service: .claude, label: "Remove me")
        await manager.activateAccount(key)
        await manager.unregister(key)

        let active = await manager.allAccounts()
        XCTAssertFalse(active.contains { $0.key == key })
    }

    func testUnregisterCreatesTombstone() async {
        let manager = await makeManager()

        let key = await manager.registerProvisional(service: .claude, label: "Tombstone me")
        await manager.activateAccount(key)
        await manager.unregister(key)

        let tombstoned = await manager.tombstonedAccounts()
        XCTAssertTrue(tombstoned.contains { $0.key == key })
    }

    func testUnregisterTombstonePreservesLastKnownLabel() async {
        let manager = await makeManager()

        let key = await manager.registerProvisional(service: .claude, label: "Original Label")
        await manager.activateAccount(key)
        await manager.unregister(key)

        let tombstoned = await manager.tombstonedAccounts()
        let entry = tombstoned.first { $0.key == key }
        XCTAssertEqual(entry?.lastKnownLabel, "Original Label")
    }

    // MARK: - allAccounts() returns only active accounts

    func testAllAccountsReturnsOnlyActiveAccounts() async {
        let manager = await makeManager()

        let provisional = await manager.registerProvisional(service: .claude, label: "Provisional")
        let toActivate = await manager.registerProvisional(service: .codex, label: "Active")
        await manager.activateAccount(toActivate)

        let active = await manager.allAccounts()
        XCTAssertFalse(active.contains { $0.key == provisional })
        XCTAssertTrue(active.contains { $0.key == toActivate })
    }

    func testAllAccountsExcludesTombstonedAccounts() async {
        let manager = await makeManager()

        let key = await manager.registerProvisional(service: .claude, label: "Will be deleted")
        await manager.activateAccount(key)
        await manager.unregister(key)

        let active = await manager.allAccounts()
        XCTAssertFalse(active.contains { $0.key == key })
    }

    func testAllAccountsReturnsEmptyWhenNoneRegistered() async {
        let manager = await makeManager()

        let active = await manager.allAccounts()
        XCTAssertTrue(active.isEmpty)
    }

    // MARK: - tombstonedAccounts() returns tombstoned accounts

    func testTombstonedAccountsReturnsOnlyTombstonedAccounts() async {
        let manager = await makeManager()

        let key = await manager.registerProvisional(service: .claude, label: "Delete me")
        await manager.activateAccount(key)
        await manager.unregister(key)

        let tombstoned = await manager.tombstonedAccounts()
        XCTAssertEqual(tombstoned.count, 1)
        XCTAssertEqual(tombstoned.first?.key, key)
    }

    func testTombstonedAccountsIsEmptyInitially() async {
        let manager = await makeManager()

        let tombstoned = await manager.tombstonedAccounts()
        XCTAssertTrue(tombstoned.isEmpty)
    }

    // MARK: - updateLabel() changes label without affecting key identity

    func testUpdateLabelChangesLabel() async {
        let manager = await makeManager()

        let key = await manager.registerProvisional(service: .claude, label: "Old Label")
        await manager.activateAccount(key)
        await manager.updateLabel(for: key, label: "New Label")

        let active = await manager.allAccounts()
        let account = active.first { $0.key == key }
        XCTAssertEqual(account?.label, "New Label")
    }

    func testUpdateLabelDoesNotChangeAccountKey() async {
        let manager = await makeManager()

        let key = await manager.registerProvisional(service: .claude, label: "Original")
        await manager.activateAccount(key)
        await manager.updateLabel(for: key, label: "Updated")

        let active = await manager.allAccounts()
        let account = active.first { $0.key == key }
        XCTAssertEqual(account?.key, key)
        XCTAssertEqual(account?.key.serviceType, .claude)
    }

    func testUpdateLabelIsNoOpForUnknownKey() async {
        let manager = await makeManager()

        let unknownKey = AccountKey(serviceType: .gemini)
        // Should not crash
        await manager.updateLabel(for: unknownKey, label: "Ghost Label")

        let active = await manager.allAccounts()
        XCTAssertTrue(active.isEmpty)
    }

    func testUpdateLabelDoesNotAffectOtherAccounts() async {
        let manager = await makeManager()

        let key1 = await manager.registerProvisional(service: .claude, label: "Account 1")
        let key2 = await manager.registerProvisional(service: .codex, label: "Account 2")
        await manager.activateAccount(key1)
        await manager.activateAccount(key2)

        await manager.updateLabel(for: key1, label: "Updated 1")

        let active = await manager.allAccounts()
        let a2 = active.first { $0.key == key2 }
        XCTAssertEqual(a2?.label, "Account 2")
    }
}
