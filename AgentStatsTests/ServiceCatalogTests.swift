import XCTest
@testable import AgentStats

final class ServiceCatalogTests: XCTestCase {

    // MARK: - authMethod(for:) — OAuth WebView services

    func testAuthMethodForClaudeReturnsOAuthWebView() {
        let method = ServiceCatalog.authMethod(for: .claude)

        guard case .oauthWebView(let url) = method else {
            XCTFail("Expected .oauthWebView but got \(method)")
            return
        }
        XCTAssertEqual(url.absoluteString, "https://claude.ai/login")
    }

    func testAuthMethodForCodexReturnsImportFromCLI() {
        let method = ServiceCatalog.authMethod(for: .codex)

        guard case .importFromCLI = method else {
            XCTFail("Expected .importFromCLI but got \(method)")
            return
        }
    }

    // MARK: - authMethod(for:) — API key services

    func testAuthMethodForGeminiReturnsApiKey() {
        let method = ServiceCatalog.authMethod(for: .gemini)

        guard case .apiKey = method else {
            XCTFail("Expected .apiKey but got \(method)")
            return
        }
    }

    func testAuthMethodForZaiReturnsApiKey() {
        let method = ServiceCatalog.authMethod(for: .zai)

        guard case .apiKey = method else {
            XCTFail("Expected .apiKey but got \(method)")
            return
        }
    }

}
