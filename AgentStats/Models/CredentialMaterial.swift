import Foundation

// MARK: - CookieDTO

/// `Codable` value-type representation of `HTTPCookie` for persistent storage.
/// `HTTPCookie` itself is not `Codable`, so this DTO bridges the gap when
/// serialising captured session cookies to disk or Keychain.
struct CookieDTO: Sendable, Codable {
    let name: String
    let value: String
    let domain: String
    let path: String
    let expiresDate: Date?
    let isSecure: Bool
    let isHTTPOnly: Bool
    /// Raw string value of the `SameSite` attribute, if present.
    let sameSite: String?

    /// Constructs a `CookieDTO` from a live `HTTPCookie` instance.
    init(from cookie: HTTPCookie) {
        name        = cookie.name
        value       = cookie.value
        domain      = cookie.domain
        path        = cookie.path
        expiresDate = cookie.expiresDate
        isSecure    = cookie.isSecure
        isHTTPOnly  = cookie.isHTTPOnly
        sameSite    = cookie.properties?[.sameSitePolicy] as? String
    }

    /// Reconstructs an `HTTPCookie` from this DTO. Returns `nil` when the
    /// underlying `HTTPCookie(properties:)` initialiser rejects the data.
    func toHTTPCookie() -> HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name:    name,
            .value:   value,
            .domain:  domain,
            .path:    path,
            .secure:  isSecure ? "TRUE" : "FALSE",
        ]
        if let expires = expiresDate {
            properties[.expires] = expires
        }
        if isHTTPOnly {
            properties[.init("HttpOnly")] = "TRUE"
        }
        if let sameSite {
            properties[.sameSitePolicy] = sameSite
        }
        return HTTPCookie(properties: properties)
    }
}

// MARK: - CredentialMaterial

/// Captured authentication state required to make authenticated API calls on
/// behalf of the user for a given service. Supports cookie-based, bearer-token,
/// and User-Agent–keyed session styles.
struct CredentialMaterial: Sendable, Codable {
    /// Session cookies extracted from the service's web interface, if any.
    let cookies: [CookieDTO]?

    /// Raw value of an `Authorization` header (e.g. `"Bearer <token>"`), if
    /// the service uses header-based authentication.
    let authorizationHeader: String?

    /// User-Agent string used during credential capture; some services tie
    /// sessions to the originating UA.
    let userAgent: String?

    /// Timestamp at which these credentials were captured.
    let capturedAt: Date

    /// Explicit expiry for the entire credential bundle. `nil` means the
    /// service did not communicate an expiry, or it is unknown.
    let expiresAt: Date?

    /// Arbitrary provider-specific metadata encoded as JSON `Data`.
    /// Used by providers that need to store structured credential objects
    /// beyond the standard cookie/header/UA fields (e.g. `CodexCredential`).
    let providerMetadata: Data?

    // MARK: Init

    init(
        cookies: [CookieDTO]?,
        authorizationHeader: String?,
        userAgent: String?,
        capturedAt: Date,
        expiresAt: Date?,
        providerMetadata: Data? = nil
    ) {
        self.cookies = cookies
        self.authorizationHeader = authorizationHeader
        self.userAgent = userAgent
        self.capturedAt = capturedAt
        self.expiresAt = expiresAt
        self.providerMetadata = providerMetadata
    }

    // MARK: Derived helpers

    /// `true` when `expiresAt` is set and is in the past.
    var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt < Date()
    }

    /// `true` when the credential is either expired or has no usable content.
    var needsReauth: Bool {
        if isExpired { return true }
        let hasCookies = !(cookies?.isEmpty ?? true)
        let hasHeader  = authorizationHeader != nil
        return !hasCookies && !hasHeader
    }

    /// Reconstructs live `HTTPCookie` objects from the stored DTOs.
    func httpCookies() -> [HTTPCookie] {
        (cookies ?? []).compactMap { $0.toHTTPCookie() }
    }
}
