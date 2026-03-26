import XCTest
@testable import AgentStats

final class ServiceTypeTests: XCTestCase {

    // MARK: - allCases count

    func testAllCasesReturnsSevenServices() {
        XCTAssertEqual(ServiceType.allCases.count, 7)
    }

    func testAllCasesContainsExpectedServices() {
        let expected: Set<ServiceType> = [.claude, .codex, .gemini, .copilot, .cursor, .opencode, .zai]
        XCTAssertEqual(Set(ServiceType.allCases), expected)
    }

    // MARK: - displayName

    func testAllServicesHaveNonEmptyDisplayName() {
        for service in ServiceType.allCases {
            XCTAssertFalse(
                service.displayName.isEmpty,
                "\(service.rawValue) has empty displayName"
            )
        }
    }

    func testKnownDisplayNames() {
        XCTAssertEqual(ServiceType.claude.displayName,   "Claude Code")
        XCTAssertEqual(ServiceType.codex.displayName,    "ChatGPT Codex")
        XCTAssertEqual(ServiceType.gemini.displayName,   "Google Gemini")
        XCTAssertEqual(ServiceType.copilot.displayName,  "GitHub Copilot")
        XCTAssertEqual(ServiceType.cursor.displayName,   "Cursor")
        XCTAssertEqual(ServiceType.opencode.displayName, "OpenCode")
        XCTAssertEqual(ServiceType.zai.displayName,      "Z.ai Coding Plan")
    }

    // MARK: - shortName

    func testAllServicesHaveNonEmptyShortName() {
        for service in ServiceType.allCases {
            XCTAssertFalse(
                service.shortName.isEmpty,
                "\(service.rawValue) has empty shortName"
            )
        }
    }

    func testKnownShortNames() {
        XCTAssertEqual(ServiceType.claude.shortName,   "Claude")
        XCTAssertEqual(ServiceType.codex.shortName,    "Codex")
        XCTAssertEqual(ServiceType.gemini.shortName,   "Gemini")
        XCTAssertEqual(ServiceType.copilot.shortName,  "Copilot")
        XCTAssertEqual(ServiceType.cursor.shortName,   "Cursor")
        XCTAssertEqual(ServiceType.opencode.shortName, "OpenCode")
        XCTAssertEqual(ServiceType.zai.shortName,      "Z.ai")
    }

    // MARK: - allowedCookieDomains

    func testClaudeHasNonEmptyAllowedCookieDomains() {
        XCTAssertFalse(ServiceType.claude.allowedCookieDomains.isEmpty)
    }

    func testCodexHasNonEmptyAllowedCookieDomains() {
        XCTAssertFalse(ServiceType.codex.allowedCookieDomains.isEmpty)
    }

    func testClaudeAllowedCookieDomainsContainsClaudeAi() {
        XCTAssertTrue(ServiceType.claude.allowedCookieDomains.contains("claude.ai"))
    }

    func testCodexAllowedCookieDomainsContainsChatgptCom() {
        XCTAssertTrue(ServiceType.codex.allowedCookieDomains.contains("chatgpt.com"))
    }

    func testCodexAllowedCookieDomainsContainsOpenAi() {
        XCTAssertTrue(ServiceType.codex.allowedCookieDomains.contains("openai.com"))
    }

    func testNonWebViewServicesReturnEmptyAllowedCookieDomains() {
        let nonWebViewServices: [ServiceType] = [.gemini, .copilot, .cursor, .opencode, .zai]
        for service in nonWebViewServices {
            XCTAssertTrue(
                service.allowedCookieDomains.isEmpty,
                "\(service.rawValue) should have empty allowedCookieDomains"
            )
        }
    }

    // MARK: - Identifiable

    func testIdEqualsRawValue() {
        for service in ServiceType.allCases {
            XCTAssertEqual(service.id, service.rawValue)
        }
    }

    // MARK: - Codable

    func testCodableRoundtrip() throws {
        for service in ServiceType.allCases {
            let data = try JSONEncoder().encode(service)
            let decoded = try JSONDecoder().decode(ServiceType.self, from: data)
            XCTAssertEqual(decoded, service)
        }
    }
}
