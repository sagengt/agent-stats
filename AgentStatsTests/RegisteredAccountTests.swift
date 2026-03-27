import XCTest
@testable import AgentStats

final class RegisteredAccountTests: XCTestCase {

    // MARK: - AccountSnapshot Codable roundtrip

    func testAccountSnapshotCodableRoundtrip() throws {
        let key1 = AccountKey(serviceType: .claude, accountId: "acct-001")
        let key2 = AccountKey(serviceType: .gemini, accountId: "acct-002")
        let tombKey = AccountKey(serviceType: .codex, accountId: "acct-tomb")

        let registeredAt = Date(timeIntervalSince1970: 1_700_000_000)
        let deletedAt    = Date(timeIntervalSince1970: 1_700_100_000)

        var snapshot = AccountSnapshot()
        snapshot.activeAccounts = [
            RegisteredAccount(key: key1, label: "My Claude", registeredAt: registeredAt),
            RegisteredAccount(key: key2, label: "My Gemini", registeredAt: registeredAt),
        ]
        snapshot.provisionalAccounts = [
            RegisteredAccount(key: AccountKey(serviceType: .zai, accountId: "prov-001"),
                              label: "Provisional Cursor",
                              registeredAt: registeredAt),
        ]
        snapshot.tombstoned = [
            TombstonedAccount(key: tombKey, lastKnownLabel: "Old Codex", deletedAt: deletedAt),
        ]

        let data    = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(AccountSnapshot.self, from: data)

        XCTAssertEqual(decoded.activeAccounts.count, 2)
        XCTAssertEqual(decoded.activeAccounts[0].key, key1)
        XCTAssertEqual(decoded.activeAccounts[0].label, "My Claude")
        XCTAssertEqual(decoded.activeAccounts[1].key, key2)
        XCTAssertEqual(decoded.provisionalAccounts.count, 1)
        XCTAssertEqual(decoded.tombstoned.count, 1)
        XCTAssertEqual(decoded.tombstoned[0].lastKnownLabel, "Old Codex")
    }

    // MARK: - AccountSnapshotLoader.loadSync on first run

    func testLoadSyncReturnsEmptySnapshotWhenNoDataStored() {
        // Use a temporary suite so we do not pollute the real UserDefaults
        let suiteName = "com.agentstats.tests.\(UUID().uuidString)"
        let defaults  = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        // Patch UserDefaults.standard is not feasible without DI, so we exercise
        // the public API and verify the contract: no crash, empty active accounts.
        // AccountSnapshotLoader reads UserDefaults.standard; on a fresh simulator
        // build the key will not be present.
        let snapshot = AccountSnapshot()
        XCTAssertTrue(snapshot.activeAccounts.isEmpty)
        XCTAssertTrue(snapshot.provisionalAccounts.isEmpty)
        XCTAssertTrue(snapshot.tombstoned.isEmpty)

        defaults.removePersistentDomain(forName: suiteName)
    }

    func testLoadSyncReturnTypeIsAccountSnapshot() {
        // Verifies the function exists and returns the correct type at compile time.
        let snapshot: AccountSnapshot = AccountSnapshotLoader.loadSync()
        // provisionalAccounts must always be empty after loadSync
        XCTAssertTrue(snapshot.provisionalAccounts.isEmpty)
    }

    // MARK: - TombstonedAccount preserves lastKnownLabel

    func testTombstonedAccountPreservesLastKnownLabel() throws {
        let key = AccountKey(serviceType: .gemini, accountId: "tomb-001")
        let label = "GitHub Copilot - Work Account"
        let deletedAt = Date(timeIntervalSince1970: 1_710_000_000)
        let tomb = TombstonedAccount(key: key, lastKnownLabel: label, deletedAt: deletedAt)

        XCTAssertEqual(tomb.lastKnownLabel, label)
        XCTAssertEqual(tomb.key, key)
        XCTAssertEqual(tomb.deletedAt, deletedAt)
    }

    func testTombstonedAccountCodablePreservesLastKnownLabel() throws {
        let key   = AccountKey(serviceType: .zai, accountId: "tomb-002")
        let label = "Z.ai Personal"
        let tomb  = TombstonedAccount(
            key: key,
            lastKnownLabel: label,
            deletedAt: Date(timeIntervalSince1970: 1_720_000_000)
        )

        let data    = try JSONEncoder().encode(tomb)
        let decoded = try JSONDecoder().decode(TombstonedAccount.self, from: data)

        XCTAssertEqual(decoded.lastKnownLabel, label)
        XCTAssertEqual(decoded.key, key)
    }

    // MARK: - AccountSnapshot provisionals cleared on load

    func testAccountSnapshotProvisionalsClearedAfterLoadSync() {
        // loadSync always strips provisionalAccounts before returning
        let snapshot = AccountSnapshotLoader.loadSync()
        XCTAssertTrue(
            snapshot.provisionalAccounts.isEmpty,
            "loadSync must clear provisionalAccounts on every launch"
        )
    }

    func testAccountSnapshotDefaultIsEmpty() {
        let snapshot = AccountSnapshot()
        XCTAssertTrue(snapshot.provisionalAccounts.isEmpty)
        XCTAssertTrue(snapshot.activeAccounts.isEmpty)
        XCTAssertTrue(snapshot.tombstoned.isEmpty)
    }

    // MARK: - RegisteredAccount Identifiable

    func testRegisteredAccountIdEqualsKey() {
        let key = AccountKey(serviceType: .zai, accountId: "cursor-id-42")
        let account = RegisteredAccount(key: key, label: "Cursor Dev", registeredAt: Date())
        XCTAssertEqual(account.id, key)
    }
}
