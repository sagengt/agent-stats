import XCTest
@testable import AgentStats

final class UsageResultStoreTests: XCTestCase {

    // MARK: - Helpers

    private func makeResult(
        serviceType: ServiceType = .claude,
        accountId: String = UUID().uuidString,
        displayData: [UsageDisplayData] = [.unavailable(reason: "test")]
    ) -> ServiceUsageResult {
        let key = AccountKey(serviceType: serviceType, accountId: accountId)
        return ServiceUsageResult(
            accountKey: key,
            displayData: displayData,
            fetchedAt: Date()
        )
    }

    // MARK: - update() stores results keyed by AccountKey

    func testUpdateStoresResultKeyedByAccountKey() async {
        let store = UsageResultStore()
        let result = makeResult(serviceType: .claude)

        await store.update(results: [result])

        let fetched = await store.result(for: result.accountKey)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.accountKey, result.accountKey)
    }

    func testUpdateReplacesExistingResultForSameKey() async {
        let store = UsageResultStore()
        let accountId = UUID().uuidString
        let key = AccountKey(serviceType: .claude, accountId: accountId)

        let first = ServiceUsageResult(
            accountKey: key,
            displayData: [.unavailable(reason: "first")],
            fetchedAt: Date()
        )
        let second = ServiceUsageResult(
            accountKey: key,
            displayData: [.unavailable(reason: "second")],
            fetchedAt: Date()
        )

        await store.update(results: [first])
        await store.update(results: [second])

        let fetched = await store.result(for: key)
        // Should hold the most recent value
        if case .unavailable(let reason) = fetched?.displayData.first {
            XCTAssertEqual(reason, "second")
        } else {
            XCTFail("Expected .unavailable display data")
        }
    }

    func testUpdateBatchStoresAllResults() async {
        let store = UsageResultStore()
        let r1 = makeResult(serviceType: .claude)
        let r2 = makeResult(serviceType: .codex)
        let r3 = makeResult(serviceType: .gemini)

        await store.update(results: [r1, r2, r3])

        let all = await store.allResults()
        XCTAssertEqual(all.count, 3)
    }

    // MARK: - allResults() returns all stored results

    func testAllResultsReturnsEmptyWhenNothingStored() async {
        let store = UsageResultStore()
        let all = await store.allResults()
        XCTAssertTrue(all.isEmpty)
    }

    func testAllResultsReturnsAllStoredResults() async {
        let store = UsageResultStore()
        let r1 = makeResult(serviceType: .claude)
        let r2 = makeResult(serviceType: .codex)

        await store.update(results: [r1, r2])

        let all = await store.allResults()
        XCTAssertEqual(all.count, 2)
        let keys = all.map(\.accountKey)
        XCTAssertTrue(keys.contains(r1.accountKey))
        XCTAssertTrue(keys.contains(r2.accountKey))
    }

    // MARK: - result(for:) returns correct result for a given AccountKey

    func testResultForKeyReturnsCorrectResult() async {
        let store = UsageResultStore()
        let r1 = makeResult(serviceType: .claude)
        let r2 = makeResult(serviceType: .codex)

        await store.update(results: [r1, r2])

        let fetched = await store.result(for: r1.accountKey)
        XCTAssertEqual(fetched?.accountKey, r1.accountKey)
        XCTAssertEqual(fetched?.serviceType, .claude)
    }

    // MARK: - result(for:) returns nil for unknown AccountKey

    func testResultForUnknownKeyReturnsNil() async {
        let store = UsageResultStore()
        let unknownKey = AccountKey(serviceType: .gemini)

        let fetched = await store.result(for: unknownKey)
        XCTAssertNil(fetched)
    }

    // MARK: - remove(account:) deletes the result for that AccountKey

    func testRemoveAccountDeletesResult() async {
        let store = UsageResultStore()
        let result = makeResult(serviceType: .claude)

        await store.update(results: [result])
        await store.remove(account: result.accountKey)

        let fetched = await store.result(for: result.accountKey)
        XCTAssertNil(fetched)
    }

    func testRemoveAccountDoesNotAffectOtherAccounts() async {
        let store = UsageResultStore()
        let r1 = makeResult(serviceType: .claude)
        let r2 = makeResult(serviceType: .codex)

        await store.update(results: [r1, r2])
        await store.remove(account: r1.accountKey)

        let all = await store.allResults()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.accountKey, r2.accountKey)
    }

    // MARK: - resultStream() emits updates when results change

    func testResultStreamEmitsCurrentStateImmediately() async {
        let store = UsageResultStore()
        let result = makeResult(serviceType: .claude)
        await store.update(results: [result])

        let stream = store.resultStream()
        var iterator = stream.makeAsyncIterator()

        // Stream should yield the current state immediately on first iteration
        let emitted = await iterator.next()
        XCTAssertNotNil(emitted)
        XCTAssertEqual(emitted?.count, 1)
        XCTAssertEqual(emitted?.first?.accountKey, result.accountKey)
    }

    func testResultStreamEmitsOnUpdate() async {
        let store = UsageResultStore()
        let result = makeResult(serviceType: .claude)

        var receivedResults: [[ServiceUsageResult]] = []
        let expectation = XCTestExpectation(description: "Stream emits at least one update")

        let task = Task {
            for await batch in store.resultStream() {
                receivedResults.append(batch)
                if receivedResults.count >= 1 {
                    expectation.fulfill()
                    break
                }
            }
        }

        // Give the stream a moment to set up
        try? await Task.sleep(for: .milliseconds(10))
        await store.update(results: [result])

        await fulfillment(of: [expectation], timeout: 1.0)
        task.cancel()
        XCTAssertFalse(receivedResults.isEmpty)
    }

    func testResultStreamEmitsOnRemove() async {
        let store = UsageResultStore()
        let result = makeResult(serviceType: .claude)
        await store.update(results: [result])

        let expectation = XCTestExpectation(description: "Stream emits after remove")
        var emissionCount = 0

        let task = Task {
            for await _ in store.resultStream() {
                emissionCount += 1
                if emissionCount >= 2 {
                    expectation.fulfill()
                    break
                }
            }
        }

        try? await Task.sleep(for: .milliseconds(10))
        await store.remove(account: result.accountKey)

        await fulfillment(of: [expectation], timeout: 1.0)
        task.cancel()
        XCTAssertGreaterThanOrEqual(emissionCount, 2)
    }

    // MARK: - Multiple accounts for same ServiceType can coexist

    func testMultipleAccountsForSameServiceTypeCoexist() async {
        let store = UsageResultStore()
        let claudeId1 = UUID().uuidString
        let claudeId2 = UUID().uuidString

        let key1 = AccountKey(serviceType: .claude, accountId: claudeId1)
        let key2 = AccountKey(serviceType: .claude, accountId: claudeId2)

        let r1 = ServiceUsageResult(accountKey: key1, displayData: [.unavailable(reason: "r1")], fetchedAt: Date())
        let r2 = ServiceUsageResult(accountKey: key2, displayData: [.unavailable(reason: "r2")], fetchedAt: Date())

        await store.update(results: [r1, r2])

        let all = await store.allResults()
        XCTAssertEqual(all.count, 2)

        let fetched1 = await store.result(for: key1)
        let fetched2 = await store.result(for: key2)
        XCTAssertNotNil(fetched1)
        XCTAssertNotNil(fetched2)
        XCTAssertEqual(fetched1?.accountKey, key1)
        XCTAssertEqual(fetched2?.accountKey, key2)
    }

    func testMultipleAccountsSameServiceTypeAreIndependent() async {
        let store = UsageResultStore()
        let key1 = AccountKey(serviceType: .claude, accountId: UUID().uuidString)
        let key2 = AccountKey(serviceType: .claude, accountId: UUID().uuidString)

        let r1 = ServiceUsageResult(accountKey: key1, displayData: [], fetchedAt: Date())
        let r2 = ServiceUsageResult(accountKey: key2, displayData: [], fetchedAt: Date())

        await store.update(results: [r1, r2])
        await store.remove(account: key1)

        let remaining = await store.result(for: key2)
        let removed = await store.result(for: key1)
        XCTAssertNotNil(remaining)
        XCTAssertNil(removed)
    }
}
