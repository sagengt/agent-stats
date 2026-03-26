import Foundation

/// Actor that orchestrates the full lifecycle of user accounts.
///
/// Responsibilities:
/// - Provisional → active → tombstoned state transitions.
/// - Delegating provider creation/removal to `AccountProviderStore`.
/// - Delegating credential cleanup to `CredentialStore`.
/// - Delegating result cleanup to `UsageResultStore`.
/// - Quiescing the `RefreshOrchestrator` before a provider is torn down so
///   stale results cannot be written after deletion.
/// - Persisting the `AccountSnapshot` to `UserDefaults` via
///   `AccountSnapshotLoader` after every mutation.
actor AccountManager {

    // MARK: - Dependencies

    private var snapshot: AccountSnapshot
    private let providerStore: AccountProviderStore
    private let credentialStore: CredentialStore
    private let resultStore: UsageResultStore
    private let orchestrator: RefreshOrchestrator

    // MARK: - Init

    init(
        snapshot: AccountSnapshot,
        providerStore: AccountProviderStore,
        credentialStore: CredentialStore,
        resultStore: UsageResultStore,
        orchestrator: RefreshOrchestrator
    ) {
        self.snapshot = snapshot
        self.providerStore = providerStore
        self.credentialStore = credentialStore
        self.resultStore = resultStore
        self.orchestrator = orchestrator
    }

    // MARK: - Registration

    /// Creates a provisional account for `service` with the given human-readable
    /// `label` and returns its `AccountKey`.
    ///
    /// Provisional accounts are persisted immediately so they survive a crash
    /// during the onboarding flow, but they are stripped from the snapshot on
    /// every cold launch (see `AccountSnapshotLoader.loadSync()`).
    func registerProvisional(service: ServiceType, label: String) async -> AccountKey {
        let key = AccountKey(serviceType: service)
        let account = RegisteredAccount(key: key, label: label, registeredAt: Date())
        snapshot.provisionalAccounts.append(account)
        persistSnapshot()
        return key
    }

    /// Promotes the provisional account identified by `key` to the active list
    /// and boots its provider.
    ///
    /// No-ops when `key` does not match any provisional account (idempotent).
    func activateAccount(_ key: AccountKey) async {
        guard let index = snapshot.provisionalAccounts.firstIndex(where: { $0.key == key }) else {
            return
        }
        let account = snapshot.provisionalAccounts.remove(at: index)
        snapshot.activeAccounts.append(account)
        await providerStore.addProvider(for: account)
        persistSnapshot()

        // Trigger an immediate refresh so the new account's data appears right away.
        AppLogger.log("[AccountManager] Account activated, requesting refresh for \(key)")
        await orchestrator.requestRefresh()
    }

    /// Removes a provisional account without creating a tombstone.
    ///
    /// Call this when the user cancels the onboarding flow after
    /// `registerProvisional` has been called but before `activateAccount`.
    func discardProvisional(_ key: AccountKey) async {
        snapshot.provisionalAccounts.removeAll { $0.key == key }
        await credentialStore.delete(for: key)
        persistSnapshot()
    }

    // MARK: - Deletion

    /// Fully removes an active account:
    /// 1. Quiesces the orchestrator for this key so in-flight fetches are
    ///    rejected before we tear down state.
    /// 2. Removes the provider from the store.
    /// 3. Deletes stored credentials and cached results.
    /// 4. Moves the account entry to the tombstone list.
    func unregister(_ key: AccountKey) async {
        // Step 1 — quiesce so the orchestrator won't write stale results.
        await orchestrator.quiesceAccount(key)

        // Step 2 — remove provider so new refreshes skip this account.
        await providerStore.remove(key)

        // Step 3 — clean up credential and result state.
        await credentialStore.delete(for: key)
        await resultStore.remove(account: key)

        // Step 4 — tombstone: move from active → tombstoned.
        if let index = snapshot.activeAccounts.firstIndex(where: { $0.key == key }) {
            let account = snapshot.activeAccounts.remove(at: index)
            let tombstone = TombstonedAccount(
                key: key,
                lastKnownLabel: account.label,
                deletedAt: Date()
            )
            snapshot.tombstoned.append(tombstone)
        }

        persistSnapshot()
    }

    // MARK: - Queries

    /// Returns all active accounts for the given service type.
    func accounts(for service: ServiceType) async -> [RegisteredAccount] {
        snapshot.activeAccounts.filter { $0.key.serviceType == service }
    }

    /// Returns every active account across all service types.
    func allAccounts() async -> [RegisteredAccount] {
        snapshot.activeAccounts
    }

    /// Returns every tombstoned (deleted) account.
    func tombstonedAccounts() async -> [TombstonedAccount] {
        snapshot.tombstoned
    }

    // MARK: - Mutation

    /// Updates the human-readable label for an active account.
    ///
    /// No-ops when `key` is not found in the active list.
    func updateLabel(for key: AccountKey, label: String) async {
        guard let index = snapshot.activeAccounts.firstIndex(where: { $0.key == key }) else {
            return
        }
        snapshot.activeAccounts[index].label = label
        persistSnapshot()
    }

    // MARK: - Private helpers

    private func persistSnapshot() {
        AccountSnapshotLoader.saveSync(snapshot)
    }
}
