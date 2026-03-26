import XCTest
@testable import AgentStats

// MARK: - Tests

final class CredentialStoreTests: XCTestCase {

    // MARK: - Helpers

    private func makeKey(serviceType: ServiceType = .claude, accountId: String = UUID().uuidString) -> AccountKey {
        AccountKey(serviceType: serviceType, accountId: accountId)
    }

    private func makeMaterial(header: String = "Bearer test-token") -> CredentialMaterial {
        CredentialMaterial(
            cookies: nil,
            authorizationHeader: header,
            userAgent: nil,
            capturedAt: Date(),
            expiresAt: nil
        )
    }

    // We test CredentialStore directly against the Keychain but use unique keys
    // per test to avoid cross-contamination. Cleanup happens in tearDown.

    private var store: CredentialStore!
    private var testKeys: [AccountKey] = []

    override func setUp() {
        super.setUp()
        store = CredentialStore()
        testKeys = []
    }

    override func tearDown() async throws {
        // Clean up any Keychain entries written during tests
        for key in testKeys {
            await store.delete(for: key)
        }
        try await super.tearDown()
    }

    private func freshKey(serviceType: ServiceType = .claude) -> AccountKey {
        let key = makeKey(serviceType: serviceType)
        testKeys.append(key)
        return key
    }

    // MARK: - save and load credential for AccountKey

    func testSaveAndLoadRoundtrip() async {
        let key = freshKey()
        let material = makeMaterial(header: "Bearer abc123")

        await store.save(for: key, material: material)
        let loaded = await store.load(for: key)

        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.authorizationHeader, "Bearer abc123")
    }

    func testLoadReturnsSavedMaterialFromCache() async {
        let key = freshKey()
        let material = makeMaterial()

        await store.save(for: key, material: material)
        // Load twice — second call hits the in-memory cache
        _ = await store.load(for: key)
        let second = await store.load(for: key)

        XCTAssertNotNil(second)
    }

    // MARK: - load returns nil for unknown AccountKey

    func testLoadReturnsNilForUnknownKey() async {
        let unknownKey = freshKey(serviceType: .gemini)
        // Immediately delete so Keychain is clean for this key
        await store.delete(for: unknownKey)

        let loaded = await store.load(for: unknownKey)
        XCTAssertNil(loaded)
    }

    // MARK: - invalidate removes credential from cache

    func testInvalidateRemovesFromCache() async {
        let key = freshKey()
        let material = makeMaterial()

        await store.save(for: key, material: material)
        await store.invalidate(for: key)

        // After invalidation the cache entry is gone; load now queries Keychain
        // which also had it deleted, so result must be nil.
        let loaded = await store.load(for: key)
        XCTAssertNil(loaded)
    }

    // MARK: - delete removes credential entirely

    func testDeleteRemovesCredential() async {
        let key = freshKey()
        let material = makeMaterial()

        await store.save(for: key, material: material)
        await store.delete(for: key)

        let loaded = await store.load(for: key)
        XCTAssertNil(loaded)
    }

    func testDeleteIsIdempotent() async {
        let key = freshKey()
        // Deleting a key that was never saved should not throw
        await store.delete(for: key)
        await store.delete(for: key)
        let loaded = await store.load(for: key)
        XCTAssertNil(loaded)
    }

    // MARK: - Multiple AccountKeys can have separate credentials

    func testMultipleAccountKeysStoreSeparately() async {
        let key1 = freshKey(serviceType: .claude)
        let key2 = freshKey(serviceType: .codex)
        let m1 = makeMaterial(header: "Bearer token-claude")
        let m2 = makeMaterial(header: "Bearer token-codex")

        await store.save(for: key1, material: m1)
        await store.save(for: key2, material: m2)

        let loaded1 = await store.load(for: key1)
        let loaded2 = await store.load(for: key2)

        XCTAssertEqual(loaded1?.authorizationHeader, "Bearer token-claude")
        XCTAssertEqual(loaded2?.authorizationHeader, "Bearer token-codex")
    }

    func testDeletingOneKeyDoesNotAffectAnother() async {
        let key1 = freshKey(serviceType: .claude)
        let key2 = freshKey(serviceType: .codex)

        await store.save(for: key1, material: makeMaterial(header: "Bearer k1"))
        await store.save(for: key2, material: makeMaterial(header: "Bearer k2"))

        await store.delete(for: key1)

        let loaded1 = await store.load(for: key1)
        let loaded2 = await store.load(for: key2)

        XCTAssertNil(loaded1)
        XCTAssertNotNil(loaded2)
        XCTAssertEqual(loaded2?.authorizationHeader, "Bearer k2")
    }

    // MARK: - Same ServiceType different accountId stores separately

    func testSameServiceTypeDifferentAccountIdStoresSeparately() async {
        let id1 = UUID().uuidString
        let id2 = UUID().uuidString
        let key1 = AccountKey(serviceType: .claude, accountId: id1)
        let key2 = AccountKey(serviceType: .claude, accountId: id2)
        testKeys.append(contentsOf: [key1, key2])

        let m1 = makeMaterial(header: "Bearer for-\(id1)")
        let m2 = makeMaterial(header: "Bearer for-\(id2)")

        await store.save(for: key1, material: m1)
        await store.save(for: key2, material: m2)

        let loaded1 = await store.load(for: key1)
        let loaded2 = await store.load(for: key2)

        XCTAssertEqual(loaded1?.authorizationHeader, "Bearer for-\(id1)")
        XCTAssertEqual(loaded2?.authorizationHeader, "Bearer for-\(id2)")
    }

    func testSameServiceTypeDifferentAccountIdCanBeDeletedIndependently() async {
        let id1 = UUID().uuidString
        let id2 = UUID().uuidString
        let key1 = AccountKey(serviceType: .claude, accountId: id1)
        let key2 = AccountKey(serviceType: .claude, accountId: id2)
        testKeys.append(contentsOf: [key1, key2])

        await store.save(for: key1, material: makeMaterial())
        await store.save(for: key2, material: makeMaterial())

        await store.delete(for: key1)

        let loaded1 = await store.load(for: key1)
        let loaded2 = await store.load(for: key2)

        XCTAssertNil(loaded1)
        XCTAssertNotNil(loaded2)
    }
}
