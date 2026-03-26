import Foundation

// MARK: - PlaceholderProvider

/// A generic stub provider for services that have not yet been implemented.
///
/// `isConfigured()` always returns `false`, so the orchestrator skips the
/// provider during refresh cycles without crashing or requiring a concrete
/// implementation.  Once a real provider is written, simply replace the
/// `PlaceholderProvider` registration in `AgentStatsApp` with the concrete type.
struct PlaceholderProvider: UsageProviderProtocol {

    // MARK: Properties

    /// The account this placeholder stands in for.
    let account: AccountKey

    /// Derived from `account.serviceType` to satisfy `UsageProviderProtocol`.
    var serviceType: ServiceType { account.serviceType }

    // MARK: UsageProviderProtocol

    /// Always returns `false`; placeholder providers are never configured.
    func isConfigured() async -> Bool { false }
}
