import Foundation

/// The complete fetch result for a single AI coding service account, containing
/// one or more display data points and the timestamp at which they were collected.
struct ServiceUsageResult: Sendable, Identifiable {
    /// The account this result belongs to.
    let accountKey: AccountKey

    /// The service this result belongs to.
    var serviceType: ServiceType { accountKey.serviceType }

    /// Ordered list of display values to render in the menu bar popover.
    /// A service may return multiple entries (e.g. several quota windows).
    let displayData: [UsageDisplayData]

    /// Wall-clock time at which the data was fetched from the service.
    let fetchedAt: Date

    /// `Identifiable` conformance keyed on service type and account ID.
    var id: String { "\(accountKey.serviceType.rawValue):\(accountKey.accountId)" }
}
