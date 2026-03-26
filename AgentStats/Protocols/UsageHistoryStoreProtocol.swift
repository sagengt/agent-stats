import Foundation

/// Defines the persistence contract for storing and querying historical usage
/// snapshots. Conformers must be `Sendable` to support actor-isolated
/// implementations.
protocol UsageHistoryStoreProtocol: Sendable {
    /// Persists a batch of freshly-fetched usage results. Each result is
    /// converted to a `UsageHistoryRecord` and appended to the store.
    ///
    /// - Parameter results: The results to record, typically the output of a
    ///   full fetch cycle across all configured providers.
    func record(results: [ServiceUsageResult]) async

    /// Returns all stored records for `service` whose `recordedAt` falls
    /// within the closed date range `[since, until]`.
    ///
    /// - Parameters:
    ///   - service:    The service to query records for.
    ///   - accountKey: When non-nil, restricts results to the specified account.
    ///                 When nil, returns records for all accounts of the service.
    ///   - since:      Inclusive lower bound of the time range.
    ///   - until:      Inclusive upper bound of the time range.
    func records(for service: ServiceType, accountKey: AccountKey?, since: Date, until: Date) async -> [UsageHistoryRecord]

    /// Returns the set of services for which at least one record exists.
    func availableServices() async -> [ServiceType]
}
