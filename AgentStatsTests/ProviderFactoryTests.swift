import XCTest
@testable import AgentStats

final class ProviderFactoryTests: XCTestCase {

    // MARK: - Helpers

    private func makeFactory() -> ProviderFactory {
        ProviderFactory(
            credentialStore: CredentialStore(),
            apiClient: APIClient()
        )
    }

    private func makeAccount(serviceType: ServiceType) -> RegisteredAccount {
        let key = AccountKey(serviceType: serviceType, accountId: UUID().uuidString)
        return RegisteredAccount(key: key, label: "\(serviceType.rawValue)-test", registeredAt: Date())
    }

    // MARK: - makeProvider for .claude

    func testMakeProviderForClaudeReturnsClaudeUsageProvider() {
        let factory = makeFactory()
        let account = makeAccount(serviceType: .claude)

        let provider = factory.makeProvider(for: account)

        XCTAssertTrue(
            provider is ClaudeUsageProvider,
            "Expected ClaudeUsageProvider but got \(type(of: provider))"
        )
    }

    func testMakeProviderForClaudeHasCorrectAccount() {
        let factory = makeFactory()
        let account = makeAccount(serviceType: .claude)

        let provider = factory.makeProvider(for: account)

        XCTAssertEqual(provider.account, account.key)
    }

    // MARK: - makeProvider for .codex

    func testMakeProviderForCodexReturnsCodexUsageProvider() {
        let factory = makeFactory()
        let account = makeAccount(serviceType: .codex)

        let provider = factory.makeProvider(for: account)

        XCTAssertTrue(
            provider is CodexUsageProvider,
            "Expected CodexUsageProvider but got \(type(of: provider))"
        )
    }

    func testMakeProviderForCodexHasCorrectAccount() {
        let factory = makeFactory()
        let account = makeAccount(serviceType: .codex)

        let provider = factory.makeProvider(for: account)

        XCTAssertEqual(provider.account, account.key)
    }

    // MARK: - makeProvider for unimplemented types (PlaceholderProvider)

    func testMakeProviderForGeminiReturnsPlaceholderProvider() {
        let factory = makeFactory()
        let account = makeAccount(serviceType: .gemini)

        let provider = factory.makeProvider(for: account)

        XCTAssertTrue(
            provider is PlaceholderProvider,
            "Expected PlaceholderProvider for .gemini but got \(type(of: provider))"
        )
    }

    func testMakeProviderForCopilotReturnsPlaceholderProvider() {
        let factory = makeFactory()
        let account = makeAccount(serviceType: .copilot)

        let provider = factory.makeProvider(for: account)

        XCTAssertTrue(provider is PlaceholderProvider)
    }

    func testMakeProviderForCursorReturnsPlaceholderProvider() {
        let factory = makeFactory()
        let account = makeAccount(serviceType: .cursor)

        let provider = factory.makeProvider(for: account)

        XCTAssertTrue(provider is PlaceholderProvider)
    }

    func testMakeProviderForOpencodeReturnsPlaceholderProvider() {
        let factory = makeFactory()
        let account = makeAccount(serviceType: .opencode)

        let provider = factory.makeProvider(for: account)

        XCTAssertTrue(provider is PlaceholderProvider)
    }

    func testMakeProviderForZaiReturnsPlaceholderProvider() {
        let factory = makeFactory()
        let account = makeAccount(serviceType: .zai)

        let provider = factory.makeProvider(for: account)

        XCTAssertTrue(provider is PlaceholderProvider)
    }

    func testPlaceholderProviderHasCorrectAccount() {
        let factory = makeFactory()
        let account = makeAccount(serviceType: .gemini)

        let provider = factory.makeProvider(for: account)

        XCTAssertEqual(provider.account, account.key)
    }

    // MARK: - PlaceholderProvider.isConfigured() returns false

    func testPlaceholderProviderIsConfiguredReturnsFalse() async {
        let factory = makeFactory()
        let account = makeAccount(serviceType: .gemini)
        let provider = factory.makeProvider(for: account)

        let configured = await provider.isConfigured()

        XCTAssertFalse(configured)
    }
}
