import Foundation

/// Phase 1 minimal stub implementing `UsageHistoryStoreProtocol`.
///
/// Stores `UsageHistoryRecord` values in memory only.
/// Full persistence (Core Data / SQLite) is planned for Phase 4.
actor UsageHistoryStore: UsageHistoryStoreProtocol {

    // MARK: - State

    private var records: [UsageHistoryRecord] = []

    // MARK: - UsageHistoryStoreProtocol

    /// Converts each `ServiceUsageResult` to a `UsageHistoryRecord` and appends it.
    func record(results: [ServiceUsageResult]) async {
        let now = Date()
        let newRecords = results.map { result in
            UsageHistoryRecord(
                schemaVersion: UsageHistoryRecord.schemaVersion,
                serviceType: result.serviceType,
                displayData: result.displayData.map { CodableUsageDisplayData(from: $0) },
                recordedAt: now
            )
        }
        records.append(contentsOf: newRecords)
    }

    /// Returns records for `service` whose `recordedAt` falls within `[since, until]`.
    func records(
        for service: ServiceType,
        since: Date,
        until: Date
    ) async -> [UsageHistoryRecord] {
        records.filter { record in
            record.serviceType == service
                && record.recordedAt >= since
                && record.recordedAt <= until
        }
    }

    /// Returns the unique service types present in the history store.
    func availableServices() async -> [ServiceType] {
        var seen = Set<ServiceType>()
        for record in records {
            seen.insert(record.serviceType)
        }
        // Preserve the canonical ordering defined by ServiceType.allCases.
        return ServiceType.allCases.filter { seen.contains($0) }
    }
}
