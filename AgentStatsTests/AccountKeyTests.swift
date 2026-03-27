import XCTest
@testable import AgentStats

final class AccountKeyTests: XCTestCase {

    // MARK: - Equality

    func testSameServiceTypeDifferentAccountIdAreNotEqual() {
        let key1 = AccountKey(serviceType: .claude, accountId: "AAA-111")
        let key2 = AccountKey(serviceType: .claude, accountId: "BBB-222")
        XCTAssertNotEqual(key1, key2)
    }

    func testSameServiceTypeAndAccountIdAreEqual() {
        let sharedId = "SHARED-ID-123"
        let key1 = AccountKey(serviceType: .gemini, accountId: sharedId)
        let key2 = AccountKey(serviceType: .gemini, accountId: sharedId)
        XCTAssertEqual(key1, key2)
    }

    func testDifferentServiceTypeSameAccountIdAreNotEqual() {
        let sharedId = "SHARED-ID-456"
        let key1 = AccountKey(serviceType: .claude, accountId: sharedId)
        let key2 = AccountKey(serviceType: .gemini, accountId: sharedId)
        XCTAssertNotEqual(key1, key2)
    }

    // MARK: - Codable roundtrip

    func testCodableRoundtrip() throws {
        let original = AccountKey(serviceType: .zai, accountId: "CURSOR-789")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AccountKey.self, from: data)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.serviceType, original.serviceType)
        XCTAssertEqual(decoded.accountId, original.accountId)
    }

    func testCodableRoundtripAllServiceTypes() throws {
        for service in ServiceType.allCases {
            let key = AccountKey(serviceType: service, accountId: "test-\(service.rawValue)")
            let data = try JSONEncoder().encode(key)
            let decoded = try JSONDecoder().decode(AccountKey.self, from: data)
            XCTAssertEqual(decoded, key, "Roundtrip failed for \(service.rawValue)")
        }
    }

    // MARK: - Hashable / Dictionary key

    func testUsableAsDictionaryKey() {
        let key1 = AccountKey(serviceType: .codex, accountId: "CODEX-001")
        let key2 = AccountKey(serviceType: .codex, accountId: "CODEX-002")
        var dict: [AccountKey: String] = [:]
        dict[key1] = "first"
        dict[key2] = "second"
        XCTAssertEqual(dict[key1], "first")
        XCTAssertEqual(dict[key2], "second")
        XCTAssertEqual(dict.count, 2)
    }

    func testEqualKeysProduceSameDictionaryEntry() {
        let sharedId = "SAME-ID"
        let key1 = AccountKey(serviceType: .zai, accountId: sharedId)
        let key2 = AccountKey(serviceType: .zai, accountId: sharedId)
        var dict: [AccountKey: Int] = [:]
        dict[key1] = 1
        dict[key2] = 2
        XCTAssertEqual(dict.count, 1)
        XCTAssertEqual(dict[key1], 2)
    }

    func testHashableEqualImpliesEqualHash() {
        let id = UUID().uuidString
        let key1 = AccountKey(serviceType: .claude, accountId: id)
        let key2 = AccountKey(serviceType: .claude, accountId: id)
        XCTAssertEqual(key1.hashValue, key2.hashValue)
    }
}
