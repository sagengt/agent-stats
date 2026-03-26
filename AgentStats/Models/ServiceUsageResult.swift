import Foundation

/// The complete fetch result for a single AI coding service, containing one
/// or more display data points and the timestamp at which they were collected.
struct ServiceUsageResult: Sendable, Identifiable {
    /// The service this result belongs to.
    let serviceType: ServiceType

    /// Ordered list of display values to render in the menu bar popover.
    /// A service may return multiple entries (e.g. several quota windows).
    let displayData: [UsageDisplayData]

    /// Wall-clock time at which the data was fetched from the service.
    let fetchedAt: Date

    /// `Identifiable` conformance keyed on the service type.
    var id: ServiceType { serviceType }
}
