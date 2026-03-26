import XCTest
@testable import AgentStats

final class CredentialMaterialTests: XCTestCase {

    // MARK: - Helpers

    private func makeCookieProperties(
        name: String = "session",
        value: String = "abc123",
        domain: String = "claude.ai",
        path: String = "/",
        secure: Bool = true,
        expires: Date? = nil
    ) -> [HTTPCookiePropertyKey: Any] {
        var props: [HTTPCookiePropertyKey: Any] = [
            .name:   name,
            .value:  value,
            .domain: domain,
            .path:   path,
            .secure: secure ? "TRUE" : "FALSE",
        ]
        if let expires { props[.expires] = expires }
        return props
    }

    // MARK: - CookieDTO roundtrip

    func testCookieDTORoundtripBasicFields() throws {
        let futureDate = Date(timeIntervalSinceNow: 3600)
        let props = makeCookieProperties(expires: futureDate)
        guard let cookie = HTTPCookie(properties: props) else {
            return XCTFail("Failed to create HTTPCookie")
        }

        let dto = CookieDTO(from: cookie)
        XCTAssertEqual(dto.name,   cookie.name)
        XCTAssertEqual(dto.value,  cookie.value)
        XCTAssertEqual(dto.domain, cookie.domain)
        XCTAssertEqual(dto.path,   cookie.path)
        XCTAssertEqual(dto.isSecure, cookie.isSecure)

        let restored = dto.toHTTPCookie()
        XCTAssertNotNil(restored, "toHTTPCookie() should succeed for valid DTO")
        XCTAssertEqual(restored?.name,  dto.name)
        XCTAssertEqual(restored?.value, dto.value)
    }

    func testCookieDTORoundtripWithoutExpiry() throws {
        let props = makeCookieProperties()
        guard let cookie = HTTPCookie(properties: props) else {
            return XCTFail("Failed to create HTTPCookie")
        }

        let dto = CookieDTO(from: cookie)
        XCTAssertNil(dto.expiresDate)
        let restored = dto.toHTTPCookie()
        XCTAssertNotNil(restored)
    }

    func testCookieDTOCodableRoundtrip() throws {
        let props = makeCookieProperties(name: "auth_token", value: "tok-xyz", secure: false)
        guard let cookie = HTTPCookie(properties: props) else {
            return XCTFail("Failed to create HTTPCookie")
        }

        let dto     = CookieDTO(from: cookie)
        let data    = try JSONEncoder().encode(dto)
        let decoded = try JSONDecoder().decode(CookieDTO.self, from: data)

        XCTAssertEqual(decoded.name,       dto.name)
        XCTAssertEqual(decoded.value,      dto.value)
        XCTAssertEqual(decoded.domain,     dto.domain)
        XCTAssertEqual(decoded.path,       dto.path)
        XCTAssertEqual(decoded.isSecure,   dto.isSecure)
        XCTAssertEqual(decoded.isHTTPOnly, dto.isHTTPOnly)
        XCTAssertEqual(decoded.sameSite,   dto.sameSite)
    }

    // MARK: - CredentialMaterial.isExpired

    func testIsExpiredReturnsTrueWhenExpiresAtIsInThePast() {
        let cred = CredentialMaterial(
            cookies: nil,
            authorizationHeader: "Bearer token",
            userAgent: nil,
            capturedAt: Date(timeIntervalSinceNow: -7200),
            expiresAt: Date(timeIntervalSinceNow: -1)   // 1 second ago
        )
        XCTAssertTrue(cred.isExpired)
    }

    func testIsExpiredReturnsFalseWhenExpiresAtIsInTheFuture() {
        let cred = CredentialMaterial(
            cookies: nil,
            authorizationHeader: "Bearer token",
            userAgent: nil,
            capturedAt: Date(),
            expiresAt: Date(timeIntervalSinceNow: 3600)  // 1 hour from now
        )
        XCTAssertFalse(cred.isExpired)
    }

    func testIsExpiredReturnsFalseWhenExpiresAtIsNil() {
        let cred = CredentialMaterial(
            cookies: nil,
            authorizationHeader: "Bearer token",
            userAgent: nil,
            capturedAt: Date(),
            expiresAt: nil
        )
        XCTAssertFalse(cred.isExpired)
    }

    // MARK: - CredentialMaterial Codable roundtrip

    func testCredentialMaterialCodableRoundtripWithAllFields() throws {
        let props = makeCookieProperties(name: "sid", value: "session-value")
        let cookie = HTTPCookie(properties: props)!
        let dto = CookieDTO(from: cookie)

        let capturedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let expiresAt  = Date(timeIntervalSince1970: 1_700_086_400)

        let original = CredentialMaterial(
            cookies: [dto],
            authorizationHeader: "Bearer abc",
            userAgent: "AgentStats/1.0",
            capturedAt: capturedAt,
            expiresAt: expiresAt
        )

        let data    = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CredentialMaterial.self, from: data)

        XCTAssertEqual(decoded.authorizationHeader, original.authorizationHeader)
        XCTAssertEqual(decoded.userAgent,           original.userAgent)
        XCTAssertEqual(decoded.capturedAt,          original.capturedAt)
        XCTAssertEqual(decoded.expiresAt,           original.expiresAt)
        XCTAssertEqual(decoded.cookies?.count,      1)
        XCTAssertEqual(decoded.cookies?.first?.name, dto.name)
    }

    func testCredentialMaterialCodableRoundtripWithNilFields() throws {
        let original = CredentialMaterial(
            cookies: nil,
            authorizationHeader: nil,
            userAgent: nil,
            capturedAt: Date(timeIntervalSince1970: 1_710_000_000),
            expiresAt: nil
        )

        let data    = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CredentialMaterial.self, from: data)

        XCTAssertNil(decoded.cookies)
        XCTAssertNil(decoded.authorizationHeader)
        XCTAssertNil(decoded.userAgent)
        XCTAssertNil(decoded.expiresAt)
    }

    // MARK: - CredentialMaterial.needsReauth

    func testNeedsReauthReturnsTrueWhenExpired() {
        let cred = CredentialMaterial(
            cookies: nil,
            authorizationHeader: "Bearer token",
            userAgent: nil,
            capturedAt: Date(),
            expiresAt: Date(timeIntervalSinceNow: -1)
        )
        XCTAssertTrue(cred.needsReauth)
    }

    func testNeedsReauthReturnsTrueWhenNoCookiesAndNoHeader() {
        let cred = CredentialMaterial(
            cookies: [],
            authorizationHeader: nil,
            userAgent: nil,
            capturedAt: Date(),
            expiresAt: nil
        )
        XCTAssertTrue(cred.needsReauth)
    }

    func testNeedsReauthReturnsFalseWhenHasAuthorizationHeader() {
        let cred = CredentialMaterial(
            cookies: nil,
            authorizationHeader: "Bearer valid-token",
            userAgent: nil,
            capturedAt: Date(),
            expiresAt: nil
        )
        XCTAssertFalse(cred.needsReauth)
    }

    // MARK: - CredentialMaterial.httpCookies()

    func testHttpCookiesReturnsEmptyArrayWhenCookiesIsNil() {
        let cred = CredentialMaterial(
            cookies: nil,
            authorizationHeader: nil,
            userAgent: nil,
            capturedAt: Date(),
            expiresAt: nil
        )
        XCTAssertTrue(cred.httpCookies().isEmpty)
    }

    func testHttpCookiesConvertsStoredDTOs() {
        let props  = makeCookieProperties(name: "csrftoken", value: "xyz987")
        let cookie = HTTPCookie(properties: props)!
        let dto    = CookieDTO(from: cookie)
        let cred   = CredentialMaterial(
            cookies: [dto],
            authorizationHeader: nil,
            userAgent: nil,
            capturedAt: Date(),
            expiresAt: nil
        )
        let httpCookies = cred.httpCookies()
        XCTAssertEqual(httpCookies.count, 1)
        XCTAssertEqual(httpCookies.first?.name, "csrftoken")
    }
}
