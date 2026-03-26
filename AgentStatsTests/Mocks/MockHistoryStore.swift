import Foundation
@testable import AgentStats

actor MockHistoryStore: UsageHistoryStoreProtocol {
    var recordedResults: [[ServiceUsageResult]] = []
    var storedRecords: [UsageHistoryRecord] = []

    func record(results: [ServiceUsageResult]) async {
        recordedResults.append(results)

        // Convert ServiceUsageResult -> UsageHistoryRecord for query support
        let newRecords = results.map { result in
            UsageHistoryRecord(
                schemaVersion: UsageHistoryRecord.schemaVersion,
                accountKey: result.accountKey,
                displayData: result.displayData.map { CodableUsageDisplayData(from: $0) },
                recordedAt: result.fetchedAt
            )
        }
        storedRecords.append(contentsOf: newRecords)
    }

    func records(
        for service: ServiceType,
        accountKey: AccountKey?,
        since: Date,
        until: Date
    ) async -> [UsageHistoryRecord] {
        storedRecords.filter { record in
            guard record.serviceType == service else { return false }
            if let key = accountKey, record.accountKey != key { return false }
            return record.recordedAt >= since && record.recordedAt <= until
        }
    }

    func availableServices() async -> [ServiceType] {
        Array(Set(storedRecords.map(\.serviceType)))
    }
}
