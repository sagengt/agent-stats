import Foundation

// MARK: - CodableUsageDisplayData

/// `Codable` mirror of `UsageDisplayData`. Because the primary enum holds
/// associated values that are not inherently `Codable` in all future cases,
/// this parallel enum is used exclusively for persistence.
enum CodableUsageDisplayData: Sendable, Codable {
    case quota(QuotaWindow)
    case tokenSummary(TokenUsageSummary)
    case activity(SessionActivity)
    case unavailable(reason: String)

    // MARK: Conversion from UsageDisplayData

    init(from displayData: UsageDisplayData) {
        switch displayData {
        case .quota(let window):
            self = .quota(window)
        case .tokenSummary(let summary):
            self = .tokenSummary(summary)
        case .activity(let session):
            self = .activity(session)
        case .unavailable(let reason):
            self = .unavailable(reason: reason)
        }
    }

    // MARK: Codable

    private enum CodingKey: String, Swift.CodingKey {
        case type, quota, tokenSummary, activity, reason
    }

    private enum TypeTag: String, Codable {
        case quota, tokenSummary, activity, unavailable
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKey.self)
        switch self {
        case .quota(let window):
            try container.encode(TypeTag.quota, forKey: .type)
            try container.encode(window, forKey: .quota)
        case .tokenSummary(let summary):
            try container.encode(TypeTag.tokenSummary, forKey: .type)
            try container.encode(summary, forKey: .tokenSummary)
        case .activity(let session):
            try container.encode(TypeTag.activity, forKey: .type)
            try container.encode(session, forKey: .activity)
        case .unavailable(let reason):
            try container.encode(TypeTag.unavailable, forKey: .type)
            try container.encode(reason, forKey: .reason)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKey.self)
        let tag = try container.decode(TypeTag.self, forKey: .type)
        switch tag {
        case .quota:
            self = .quota(try container.decode(QuotaWindow.self, forKey: .quota))
        case .tokenSummary:
            self = .tokenSummary(try container.decode(TokenUsageSummary.self, forKey: .tokenSummary))
        case .activity:
            self = .activity(try container.decode(SessionActivity.self, forKey: .activity))
        case .unavailable:
            self = .unavailable(reason: try container.decode(String.self, forKey: .reason))
        }
    }
}

// MARK: - UsageHistoryRecord

/// A single persisted snapshot of usage data for one service account. The
/// `schemaVersion` field allows future migrations without breaking
/// existing stored records.
struct UsageHistoryRecord: Sendable, Codable {
    /// Current on-disk schema version. Increment when the layout changes in a
    /// backwards-incompatible way and provide a migration path.
    static let schemaVersion: Int = 2

    /// The schema version this record was written with.
    let schemaVersion: Int

    /// The account this record belongs to.
    let accountKey: AccountKey

    /// Service this record belongs to.
    var serviceType: ServiceType { accountKey.serviceType }

    /// Ordered list of usage values captured at `recordedAt`.
    let displayData: [CodableUsageDisplayData]

    /// Wall-clock time at which the snapshot was taken.
    let recordedAt: Date
}
