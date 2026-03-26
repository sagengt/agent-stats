import XCTest
@testable import AgentStats

final class PlaceholderProviderTests: XCTestCase {

    // MARK: - Helpers

    private func makeKey(serviceType: ServiceType) -> AccountKey {
        AccountKey(serviceType: serviceType, accountId: UUID().uuidString)
    }

    // MARK: - serviceType

    func testServiceTypeMatchesAccountKeyServiceType() {
        let key = makeKey(serviceType: .gemini)
        let provider = PlaceholderProvider(account: key)

        XCTAssertEqual(provider.serviceType, .gemini)
    }

    func testServiceTypeMatchesAccountKeyServiceTypeForCopilot() {
        let key = makeKey(serviceType: .copilot)
        let provider = PlaceholderProvider(account: key)

        XCTAssertEqual(provider.serviceType, .copilot)
    }

    func testServiceTypeMatchesAccountKeyServiceTypeForCursor() {
        let key = makeKey(serviceType: .cursor)
        let provider = PlaceholderProvider(account: key)

        XCTAssertEqual(provider.serviceType, .cursor)
    }

    func testServiceTypeMatchesAccountKeyServiceTypeForOpencode() {
        let key = makeKey(serviceType: .opencode)
        let provider = PlaceholderProvider(account: key)

        XCTAssertEqual(provider.serviceType, .opencode)
    }

    func testServiceTypeMatchesAccountKeyServiceTypeForZai() {
        let key = makeKey(serviceType: .zai)
        let provider = PlaceholderProvider(account: key)

        XCTAssertEqual(provider.serviceType, .zai)
    }

    // MARK: - account property

    func testAccountReturnsTheKeyPassedAtInit() {
        let key = makeKey(serviceType: .gemini)
        let provider = PlaceholderProvider(account: key)

        XCTAssertEqual(provider.account, key)
    }

    func testAccountIdIsPreserved() {
        let fixedId = "fixed-account-id-1234"
        let key = AccountKey(serviceType: .cursor, accountId: fixedId)
        let provider = PlaceholderProvider(account: key)

        XCTAssertEqual(provider.account.accountId, fixedId)
    }

    // MARK: - isConfigured() always returns false

    func testIsConfiguredAlwaysReturnsFalse() async {
        let key = makeKey(serviceType: .gemini)
        let provider = PlaceholderProvider(account: key)

        let result = await provider.isConfigured()

        XCTAssertFalse(result)
    }

    func testIsConfiguredAlwaysReturnsFalseForAllServiceTypes() async {
        // Verify the invariant holds for every service type that falls back to
        // PlaceholderProvider (i.e. services without a concrete implementation).
        let unimplementedTypes: [ServiceType] = [.gemini, .copilot, .cursor, .opencode, .zai]

        for serviceType in unimplementedTypes {
            let key = makeKey(serviceType: serviceType)
            let provider = PlaceholderProvider(account: key)

            let result = await provider.isConfigured()
            XCTAssertFalse(result, "Expected isConfigured() == false for .\(serviceType.rawValue)")
        }
    }
}
