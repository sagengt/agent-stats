import XCTest
@testable import AgentStats

final class UsageHistoryStoreTests: XCTestCase {

    // MARK: - Helpers

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgentStatsTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func makeStore() -> UsageHistoryStore {
        UsageHistoryStore(storageDirectory: tempDir)
    }

    private func makeResult(
        serviceType: ServiceType,
        accountId: String = UUID().uuidString,
        fetchedAt: Date = Date()
    ) -> ServiceUsageResult {
        let key = AccountKey(serviceType: serviceType, accountId: accountId)
        return ServiceUsageResult(
            accountKey: key,
            displayData: [.unavailable(reason: "test")],
            fetchedAt: fetchedAt
        )
    }

    private func date(daysAgo: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
    }

    // MARK: - record() appends UsageHistoryRecords with correct accountKey

    func testRecordAppendsRecordsWithCorrectAccountKey() async {
        let store = makeStore()
        let result = makeResult(serviceType: .claude)

        await store.record(results: [result])

        let since = date(daysAgo: 1)
        let until = Date()
        let records = await store.records(for: .claude, accountKey: result.accountKey, since: since, until: until)

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.accountKey, result.accountKey)
    }

    func testRecordAppendsBatchResults() async {
        let store = makeStore()
        let r1 = makeResult(serviceType: .claude)
        let r2 = makeResult(serviceType: .claude)

        await store.record(results: [r1, r2])

        let since = date(daysAgo: 1)
        let until = Date()
        let records = await store.records(for: .claude, accountKey: nil, since: since, until: until)

        XCTAssertEqual(records.count, 2)
    }

    func testRecordMultipleBatchesAccumulatesRecords() async {
        let store = makeStore()
        let r1 = makeResult(serviceType: .claude)
        let r2 = makeResult(serviceType: .claude)

        await store.record(results: [r1])
        await store.record(results: [r2])

        let since = date(daysAgo: 1)
        let until = Date()
        let records = await store.records(for: .claude, accountKey: nil, since: since, until: until)

        XCTAssertEqual(records.count, 2)
    }

    // MARK: - records(for:accountKey:since:until:) filters by service and date range

    func testRecordsFiltersByService() async {
        let store = makeStore()
        let claudeResult = makeResult(serviceType: .claude)
        let codexResult = makeResult(serviceType: .codex)

        await store.record(results: [claudeResult, codexResult])

        let since = date(daysAgo: 1)
        let until = Date()
        let claudeRecords = await store.records(for: .claude, accountKey: nil, since: since, until: until)
        let codexRecords = await store.records(for: .codex, accountKey: nil, since: since, until: until)

        XCTAssertEqual(claudeRecords.count, 1)
        XCTAssertEqual(claudeRecords.first?.serviceType, .claude)
        XCTAssertEqual(codexRecords.count, 1)
        XCTAssertEqual(codexRecords.first?.serviceType, .codex)
    }

    func testRecordsFiltersOutOfRangeDates() async {
        let store = makeStore()
        // record() uses Date() internally for recordedAt, so record is always "now"
        let result = makeResult(serviceType: .claude)
        await store.record(results: [result])

        // Query for a range far in the past — current record should be excluded
        let since = date(daysAgo: 30)
        let until = date(daysAgo: 20)
        let records = await store.records(for: .claude, accountKey: nil, since: since, until: until)

        XCTAssertTrue(records.isEmpty)
    }

    func testRecordsIncludesRecordsAtCurrentTime() async {
        let store = makeStore()
        let result = makeResult(serviceType: .claude)
        await store.record(results: [result])

        // record() uses Date() for recordedAt, so query a range that includes now
        let since = date(daysAgo: 1)
        let until = Date().addingTimeInterval(60) // 1 minute buffer
        let records = await store.records(for: .claude, accountKey: nil, since: since, until: until)

        XCTAssertEqual(records.count, 1)
    }

    func testRecordsExcludesResultsWhenQueryRangeIsFuture() async {
        let store = makeStore()
        let result = makeResult(serviceType: .claude)
        await store.record(results: [result])

        // Query for a future range — current record should be excluded
        let since = Date().addingTimeInterval(3600)
        let until = Date().addingTimeInterval(7200)
        let records = await store.records(for: .claude, accountKey: nil, since: since, until: until)

        XCTAssertTrue(records.isEmpty)
    }

    // MARK: - records(for:accountKey:since:until:) filters by accountKey when non-nil

    func testRecordsFiltersByAccountKeyWhenProvided() async {
        let store = makeStore()
        let idA = UUID().uuidString
        let idB = UUID().uuidString
        let resultA = makeResult(serviceType: .claude, accountId: idA)
        let resultB = makeResult(serviceType: .claude, accountId: idB)

        await store.record(results: [resultA, resultB])

        let since = date(daysAgo: 1)
        let until = Date()
        let filtered = await store.records(for: .claude, accountKey: resultA.accountKey, since: since, until: until)

        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.accountKey, resultA.accountKey)
    }

    func testRecordsReturnsOnlyMatchingAccountKey() async {
        let store = makeStore()
        let idA = UUID().uuidString
        let idB = UUID().uuidString
        let resultA = makeResult(serviceType: .claude, accountId: idA)
        let resultB = makeResult(serviceType: .claude, accountId: idB)

        await store.record(results: [resultA, resultB])

        let since = date(daysAgo: 1)
        let until = Date()
        let forB = await store.records(for: .claude, accountKey: resultB.accountKey, since: since, until: until)

        XCTAssertFalse(forB.isEmpty)
        XCTAssertTrue(forB.allSatisfy { $0.accountKey == resultB.accountKey })
    }

    // MARK: - records(for:accountKey:since:until:) returns all accounts when accountKey is nil

    func testRecordsReturnsAllAccountsWhenAccountKeyIsNil() async {
        let store = makeStore()
        let id1 = UUID().uuidString
        let id2 = UUID().uuidString
        let r1 = makeResult(serviceType: .claude, accountId: id1)
        let r2 = makeResult(serviceType: .claude, accountId: id2)

        await store.record(results: [r1, r2])

        let since = date(daysAgo: 1)
        let until = Date()
        let all = await store.records(for: .claude, accountKey: nil, since: since, until: until)

        XCTAssertEqual(all.count, 2)
    }

    // MARK: - availableServices() returns unique ServiceTypes

    func testAvailableServicesReturnsUniqueServiceTypes() async {
        let store = makeStore()
        let r1 = makeResult(serviceType: .claude)
        let r2 = makeResult(serviceType: .claude) // duplicate service
        let r3 = makeResult(serviceType: .codex)

        await store.record(results: [r1, r2, r3])

        let services = await store.availableServices()

        // Should return each service type only once
        XCTAssertEqual(services.count, 2)
        XCTAssertTrue(services.contains(.claude))
        XCTAssertTrue(services.contains(.codex))
    }

    func testAvailableServicesReturnsEmptyWhenNoRecords() async {
        let store = makeStore()
        let services = await store.availableServices()
        XCTAssertTrue(services.isEmpty)
    }

    func testAvailableServicesRespectsCanonicalOrdering() async {
        let store = makeStore()
        // Insert in reverse canonical order
        let codexResult = makeResult(serviceType: .codex)
        let claudeResult = makeResult(serviceType: .claude)
        await store.record(results: [codexResult, claudeResult])

        let services = await store.availableServices()
        // ServiceType.allCases defines canonical order: claude comes before codex
        let claudeIndex = services.firstIndex(of: .claude)
        let codexIndex = services.firstIndex(of: .codex)
        XCTAssertNotNil(claudeIndex)
        XCTAssertNotNil(codexIndex)
        XCTAssertLessThan(claudeIndex!, codexIndex!)
    }
}
