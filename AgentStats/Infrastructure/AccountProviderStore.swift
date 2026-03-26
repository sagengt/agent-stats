import Foundation

/// Actor that manages the live mapping from `AccountKey` to provider instances.
///
/// Constructed once at app startup. `AccountManager` calls `addProvider` /
/// `remove` as accounts are registered or deleted; `RefreshOrchestrator` calls
/// `allProviders()` on every refresh cycle.
actor AccountProviderStore {

    // MARK: - State

    private var providers: [AccountKey: any UsageProviderProtocol] = [:]

    // MARK: - Dependencies

    private let factory: ProviderFactory

    // MARK: - Init

    /// Bootstraps the store by creating a provider for every account that is
    /// already active in the persisted snapshot.
    init(accounts: [RegisteredAccount], factory: ProviderFactory) {
        self.factory = factory
        for account in accounts {
            providers[account.key] = factory.makeProvider(for: account)
        }
    }

    // MARK: - Public API

    /// Returns the provider registered for `key`, or `nil` if not found.
    func provider(for key: AccountKey) -> (any UsageProviderProtocol)? {
        providers[key]
    }

    /// Returns every currently registered provider.
    ///
    /// Used by `RefreshOrchestrator` to drive the fetch cycle.
    func allProviders() -> [any UsageProviderProtocol] {
        Array(providers.values)
    }

    /// Creates a provider for `account` using the factory and registers it.
    ///
    /// If a provider already exists for the same key it is replaced.
    func addProvider(for account: RegisteredAccount) async {
        providers[account.key] = factory.makeProvider(for: account)
    }

    /// Removes the provider registered for `key`.
    ///
    /// No-ops silently when the key is not found.
    func remove(_ key: AccountKey) async {
        providers.removeValue(forKey: key)
    }
}
