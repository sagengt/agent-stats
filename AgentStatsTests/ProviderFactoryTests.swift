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

    // MARK: - makeProvider for Phase 3 providers

    func testMakeProviderForGeminiReturnsGeminiProvider() {
        let factory = makeFactory()
        let account = makeAccount(serviceType: .gemini)
        let provider = factory.makeProvider(for: account)
        XCTAssertTrue(provider is GeminiUsageProvider, "Expected GeminiUsageProvider but got \(type(of: provider))")
    }

    func testMakeProviderForCopilotReturnsCopilotProvider() {
        let factory = makeFactory()
        let account = makeAccount(serviceType: .copilot)
        let provider = factory.makeProvider(for: account)
        XCTAssertTrue(provider is CopilotUsageProvider, "Expected CopilotUsageProvider but got \(type(of: provider))")
    }

    func testMakeProviderForCursorReturnsCursorProvider() {
        let factory = makeFactory()
        let account = makeAccount(serviceType: .cursor)
        let provider = factory.makeProvider(for: account)
        XCTAssertTrue(provider is CursorUsageProvider, "Expected CursorUsageProvider but got \(type(of: provider))")
    }

    func testMakeProviderForOpencodeReturnsOpenCodeProvider() {
        let factory = makeFactory()
        let account = makeAccount(serviceType: .opencode)
        let provider = factory.makeProvider(for: account)
        XCTAssertTrue(provider is OpenCodeUsageProvider, "Expected OpenCodeUsageProvider but got \(type(of: provider))")
    }

    func testMakeProviderForZaiReturnsZaiProvider() {
        let factory = makeFactory()
        let account = makeAccount(serviceType: .zai)
        let provider = factory.makeProvider(for: account)
        XCTAssertTrue(provider is ZaiUsageProvider, "Expected ZaiUsageProvider but got \(type(of: provider))")
    }

    func testAllProvidersHaveCorrectAccount() {
        let factory = makeFactory()
        for service in ServiceType.allCases {
            let account = makeAccount(serviceType: service)
            let provider = factory.makeProvider(for: account)
            XCTAssertEqual(provider.account, account.key, "Account mismatch for \(service)")
        }
    }
}
