import XCTest
@testable import AgentStats

final class UsageHistoryTests: XCTestCase {

    // MARK: - Helpers

    private func makeQuotaWindow() -> QuotaWindow {
        QuotaWindow(
            id: "5h",
            label: "5 Hour",
            usedPercentage: 0.42,
            resetAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    private func makeTokenSummary() -> TokenUsageSummary {
        TokenUsageSummary(
            totalTokens: 10_000,
            inputTokens: 6_000,
            outputTokens: 4_000,
            costUSD: 0.25,
            period: .thisMonth
        )
    }

    private func makeSessionActivity() -> SessionActivity {
        SessionActivity(
            activeSessions: 3,
            totalDurationMinutes: 120,
            requestCount: 45,
            lastActiveAt: Date(timeIntervalSince1970: 1_700_500_000)
        )
    }

    // MARK: - CodableUsageDisplayData init(from: UsageDisplayData)

    func testInitFromQuotaUsageDisplayData() {
        let window = makeQuotaWindow()
        let codable = CodableUsageDisplayData(from: .quota(window))
        if case .quota(let decoded) = codable {
            XCTAssertEqual(decoded.id, window.id)
            XCTAssertEqual(decoded.label, window.label)
            XCTAssertEqual(decoded.usedPercentage, window.usedPercentage)
            XCTAssertEqual(decoded.resetAt, window.resetAt)
        } else {
            XCTFail("Expected .quota case")
        }
    }

    func testInitFromTokenSummaryUsageDisplayData() {
        let summary = makeTokenSummary()
        let codable = CodableUsageDisplayData(from: .tokenSummary(summary))
        if case .tokenSummary(let decoded) = codable {
            XCTAssertEqual(decoded.totalTokens, summary.totalTokens)
            XCTAssertEqual(decoded.inputTokens, summary.inputTokens)
            XCTAssertEqual(decoded.outputTokens, summary.outputTokens)
            XCTAssertEqual(decoded.costUSD, summary.costUSD)
            XCTAssertEqual(decoded.period, summary.period)
        } else {
            XCTFail("Expected .tokenSummary case")
        }
    }

    func testInitFromActivityUsageDisplayData() {
        let activity = makeSessionActivity()
        let codable = CodableUsageDisplayData(from: .activity(activity))
        if case .activity(let decoded) = codable {
            XCTAssertEqual(decoded.activeSessions, activity.activeSessions)
            XCTAssertEqual(decoded.totalDurationMinutes, activity.totalDurationMinutes)
            XCTAssertEqual(decoded.requestCount, activity.requestCount)
            XCTAssertEqual(decoded.lastActiveAt, activity.lastActiveAt)
        } else {
            XCTFail("Expected .activity case")
        }
    }

    func testInitFromUnavailableUsageDisplayData() {
        let reason = "Network error: timeout"
        let codable = CodableUsageDisplayData(from: .unavailable(reason: reason))
        if case .unavailable(let decodedReason) = codable {
            XCTAssertEqual(decodedReason, reason)
        } else {
            XCTFail("Expected .unavailable case")
        }
    }

    // MARK: - CodableUsageDisplayData Codable roundtrip

    func testCodableRoundtripQuota() throws {
        let window = makeQuotaWindow()
        let original = CodableUsageDisplayData.quota(window)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CodableUsageDisplayData.self, from: data)
        guard case .quota(let decodedWindow) = decoded else {
            return XCTFail("Expected .quota after decode")
        }
        XCTAssertEqual(decodedWindow.id, window.id)
        XCTAssertEqual(decodedWindow.usedPercentage, window.usedPercentage)
        XCTAssertEqual(decodedWindow.resetAt, window.resetAt)
    }

    func testCodableRoundtripTokenSummary() throws {
        let summary  = makeTokenSummary()
        let original = CodableUsageDisplayData.tokenSummary(summary)
        let data     = try JSONEncoder().encode(original)
        let decoded  = try JSONDecoder().decode(CodableUsageDisplayData.self, from: data)
        guard case .tokenSummary(let s) = decoded else {
            return XCTFail("Expected .tokenSummary after decode")
        }
        XCTAssertEqual(s.totalTokens, summary.totalTokens)
        XCTAssertEqual(s.costUSD, summary.costUSD)
        XCTAssertEqual(s.period, summary.period)
    }

    func testCodableRoundtripActivity() throws {
        let activity = makeSessionActivity()
        let original = CodableUsageDisplayData.activity(activity)
        let data     = try JSONEncoder().encode(original)
        let decoded  = try JSONDecoder().decode(CodableUsageDisplayData.self, from: data)
        guard case .activity(let a) = decoded else {
            return XCTFail("Expected .activity after decode")
        }
        XCTAssertEqual(a.activeSessions, activity.activeSessions)
        XCTAssertEqual(a.requestCount, activity.requestCount)
    }

    func testCodableRoundtripUnavailable() throws {
        let reason   = "Quota exceeded"
        let original = CodableUsageDisplayData.unavailable(reason: reason)
        let data     = try JSONEncoder().encode(original)
        let decoded  = try JSONDecoder().decode(CodableUsageDisplayData.self, from: data)
        guard case .unavailable(let r) = decoded else {
            return XCTFail("Expected .unavailable after decode")
        }
        XCTAssertEqual(r, reason)
    }

    // MARK: - UsageHistoryRecord schema version

    func testSchemaVersionIsTwo() {
        XCTAssertEqual(UsageHistoryRecord.schemaVersion, 2)
    }

    func testInstanceSchemaVersionMatchesStaticConstant() {
        let key    = AccountKey(serviceType: .claude, accountId: "schema-test")
        let record = UsageHistoryRecord(
            schemaVersion: UsageHistoryRecord.schemaVersion,
            accountKey: key,
            displayData: [],
            recordedAt: Date()
        )
        XCTAssertEqual(record.schemaVersion, UsageHistoryRecord.schemaVersion)
    }

    // MARK: - UsageHistoryRecord.serviceType computed property

    func testServiceTypeComputedPropertyReturnsAccountKeyServiceType() {
        for service in ServiceType.allCases {
            let key = AccountKey(serviceType: service, accountId: "svc-test")
            let record = UsageHistoryRecord(
                schemaVersion: UsageHistoryRecord.schemaVersion,
                accountKey: key,
                displayData: [],
                recordedAt: Date()
            )
            XCTAssertEqual(
                record.serviceType, service,
                "serviceType mismatch for \(service.rawValue)"
            )
        }
    }

    // MARK: - UsageHistoryRecord Codable roundtrip

    func testUsageHistoryRecordCodableRoundtrip() throws {
        let key      = AccountKey(serviceType: .gemini, accountId: "gemini-hist-01")
        let window   = makeQuotaWindow()
        let recordedAt = Date(timeIntervalSince1970: 1_750_000_000)
        let record   = UsageHistoryRecord(
            schemaVersion: UsageHistoryRecord.schemaVersion,
            accountKey: key,
            displayData: [.quota(window), .unavailable(reason: "partial")],
            recordedAt: recordedAt
        )

        let data    = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(UsageHistoryRecord.self, from: data)

        XCTAssertEqual(decoded.schemaVersion, record.schemaVersion)
        XCTAssertEqual(decoded.accountKey, record.accountKey)
        XCTAssertEqual(decoded.recordedAt, record.recordedAt)
        XCTAssertEqual(decoded.displayData.count, 2)
    }
}
