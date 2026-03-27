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
        XCTAssertEqual(url.absoluteString, "https://claude.ai")
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

    // MARK: - authMethod(for:) — Personal access token

    func testAuthMethodForCopilotReturnsPersonalAccessToken() {
        let method = ServiceCatalog.authMethod(for: .copilot)

        guard case .personalAccessToken = method else {
            XCTFail("Expected .personalAccessToken but got \(method)")
            return
        }
    }

    // MARK: - authMethod(for:) — None

    func testAuthMethodForCursorReturnsNone() {
        let method = ServiceCatalog.authMethod(for: .cursor)

        guard case .none = method else {
            XCTFail("Expected .none but got \(method)")
            return
        }
    }

    func testAuthMethodForOpencodeReturnsNone() {
        let method = ServiceCatalog.authMethod(for: .opencode)

        guard case .none = method else {
            XCTFail("Expected .none but got \(method)")
            return
        }
    }
}
