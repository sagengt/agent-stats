import Foundation

// MARK: - ProviderRegistry

/// Central registry mapping each `ServiceType` to its concrete provider.
///
/// Constructed once at app startup and passed through the dependency graph.
/// `@unchecked Sendable` is safe because `providersByService` is written only
/// during `init` and is read-only afterwards.
final class ProviderRegistry: @unchecked Sendable {

    // MARK: Storage

    let providersByService: [ServiceType: any UsageProviderProtocol]

    // MARK: Init

    init(providers: [any UsageProviderProtocol]) {
        var dict: [ServiceType: any UsageProviderProtocol] = [:]
        for provider in providers {
            dict[provider.serviceType] = provider
        }
        self.providersByService = dict
    }

    // MARK: Typed accessors

    /// All registered providers that conform to `QuotaWindowProvider`.
    var quotaProviders: [any QuotaWindowProvider] {
        providersByService.values.compactMap { $0 as? any QuotaWindowProvider }
    }

    /// All registered providers that conform to `TokenUsageProvider`.
    var tokenProviders: [any TokenUsageProvider] {
        providersByService.values.compactMap { $0 as? any TokenUsageProvider }
    }

    /// All registered providers that conform to `SessionActivityProvider`.
    var activityProviders: [any SessionActivityProvider] {
        providersByService.values.compactMap { $0 as? any SessionActivityProvider }
    }

    /// Every registered provider regardless of capability.
    /// Used by `RefreshOrchestrator` to drive the fetch cycle.
    func allProviders() -> [any UsageProviderProtocol] {
        Array(providersByService.values)
    }

    /// Convenience alias kept for backwards-compatibility with call sites
    /// that reference `allConfiguredProviders`.
    var allConfiguredProviders: [any UsageProviderProtocol] {
        allProviders()
    }
}
