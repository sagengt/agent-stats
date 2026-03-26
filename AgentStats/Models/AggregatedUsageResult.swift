import Foundation

struct AggregatedUsageResult: Sendable, Identifiable {
    let serviceType: ServiceType
    let displayData: [UsageDisplayData]
    let sourceAccountCount: Int
    let aggregatedAt: Date
    var id: ServiceType { serviceType }
}
