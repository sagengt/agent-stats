import Foundation

/// Fetches ChatGPT Codex (OpenAI) quota consumption from the ChatGPT backend
/// API.
///
/// Authentication flow:
/// 1. Session cookies captured via the OAuth WebView login are used to call
///    `https://chatgpt.com/api/auth/session`, which returns a short-lived
///    access token in its JSON body.
/// 2. That access token is then forwarded as a Bearer token in the
///    `Authorization` header when calling the WHAM usage endpoint.
///
/// This avoids relying on `WKNavigationDelegate` response-header interception
/// (which cannot reliably capture bearer tokens) and mirrors the approach used
/// by the Claude provider.
///
/// Implements `QuotaWindowProvider` (usage window) and
/// `CredentialRequired` (OAuth via chatgpt.com).
struct CodexUsageProvider: QuotaWindowProvider, CredentialRequired {

    // MARK: Protocol requirements

    let serviceType: ServiceType = .codex
    let authMethod: AuthMethod = .oauthWebView(loginURL: URL(string: "https://chatgpt.com")!)

    // MARK: Dependencies

    private let credentialStore: CredentialStore
    private let apiClient: APIClient

    // MARK: Init

    init(credentialStore: CredentialStore, apiClient: APIClient = .shared) {
        self.credentialStore = credentialStore
        self.apiClient = apiClient
    }

    // MARK: UsageProviderProtocol

    func isConfigured() async -> Bool {
        guard let credential = await credentialStore.load(for: .codex) else { return false }
        return !credential.isExpired && !credential.needsReauth
    }

    // MARK: QuotaWindowProvider

    func fetchQuotaWindows() async throws -> [QuotaWindow] {
        guard let credential = await credentialStore.load(for: .codex) else {
            throw ProviderError.notAuthenticated
        }

        guard !credential.isExpired else {
            throw ProviderError.notAuthenticated
        }

        // Step 1 — exchange session cookies for a short-lived access token.
        // The `/api/auth/session` endpoint accepts cookies and returns a JSON
        // body containing `{ "accessToken": "Bearer …" }`.
        let accessToken: String
        do {
            accessToken = try await fetchAccessToken(using: credential)
        } catch APIError.unauthorized {
            throw ProviderError.notAuthenticated
        } catch let providerError as ProviderError {
            throw providerError
        } catch {
            throw ProviderError.fetchFailed("Session token exchange failed: \(error.localizedDescription)")
        }

        // Step 2 — call the WHAM usage endpoint with the access token.
        let headers = buildHeaders(from: credential, accessToken: accessToken)
        let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!

        do {
            let raw = try await apiClient.fetchRaw(from: usageURL, headers: headers)
            return try parseQuotaWindows(from: raw)
        } catch APIError.unauthorized {
            throw ProviderError.notAuthenticated
        } catch let providerError as ProviderError {
            throw providerError
        } catch {
            throw ProviderError.fetchFailed(error.localizedDescription)
        }
    }

    // MARK: Session token exchange

    /// Calls `https://chatgpt.com/api/auth/session` using only the stored
    /// session cookies to obtain a short-lived bearer access token.
    ///
    /// - Returns: The raw access token string (without the `Bearer ` prefix).
    /// - Throws: `ProviderError.notAuthenticated` when the session endpoint
    ///   returns 401, or `ProviderError.parseError` when the response body
    ///   cannot be decoded.
    private func fetchAccessToken(using credential: CredentialMaterial) async throws -> String {
        let sessionURL = URL(string: "https://chatgpt.com/api/auth/session")!

        // Build a cookie-only header set — no Authorization header yet.
        var sessionHeaders: [String: String] = [:]
        let cookieHeader = credential.httpCookies()
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")
        if !cookieHeader.isEmpty {
            sessionHeaders["Cookie"] = cookieHeader
        }
        if let userAgent = credential.userAgent {
            sessionHeaders["User-Agent"] = userAgent
        } else {
            sessionHeaders["User-Agent"] = "AgentStats/1.0 macOS"
        }
        sessionHeaders["Accept"] = "application/json"
        sessionHeaders["Referer"] = "https://chatgpt.com/"

        let raw = try await apiClient.fetchRaw(from: sessionURL, headers: sessionHeaders)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let sessionResponse = try decoder.decode(ChatGPTSessionResponse.self, from: raw)

        guard let token = sessionResponse.accessToken, !token.isEmpty else {
            throw ProviderError.notAuthenticated
        }
        return token
    }

    // MARK: Private helpers

    /// Builds headers for the WHAM usage endpoint.
    ///
    /// - Parameters:
    ///   - credential:   Stored credential material (cookies, user-agent).
    ///   - accessToken:  Short-lived bearer token obtained from the session endpoint.
    private func buildHeaders(
        from credential: CredentialMaterial,
        accessToken: String
    ) -> [String: String] {
        var headers: [String: String] = [:]

        // Use the access token obtained from the session API as the bearer token.
        headers["Authorization"] = "Bearer \(accessToken)"

        // Session cookies provide additional anti-CSRF protection.
        let cookieHeader = credential.httpCookies()
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")
        if !cookieHeader.isEmpty {
            headers["Cookie"] = cookieHeader
        }

        if let userAgent = credential.userAgent {
            headers["User-Agent"] = userAgent
        } else {
            headers["User-Agent"] = "AgentStats/1.0 macOS"
        }

        headers["Accept"] = "application/json"
        headers["Content-Type"] = "application/json"
        // Required by the ChatGPT backend to distinguish API requests from browser navigations.
        headers["Referer"] = "https://chatgpt.com/"
        headers["Origin"] = "https://chatgpt.com"

        return headers
    }

    private func parseQuotaWindows(from data: Data) throws -> [QuotaWindow] {
        // ChatGPT WHAM usage API response shape (approximate):
        // {
        //   "usage": {
        //     "codex": {
        //       "used": 12,
        //       "limit": 50,
        //       "reset_at": "2025-01-28T00:00:00Z"
        //     }
        //   }
        // }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601

        do {
            let envelope = try decoder.decode(WHAMUsageEnvelope.self, from: data)
            return envelope.toQuotaWindows()
        } catch {
            throw ProviderError.parseError(error.localizedDescription)
        }
    }
}

// MARK: - Response models (private)

/// Minimal representation of the `/api/auth/session` response from chatgpt.com.
/// Only the `accessToken` field is needed; other fields are ignored.
private struct ChatGPTSessionResponse: Decodable {
    /// Short-lived JWT or opaque bearer token. `nil` when the session is invalid
    /// or the user is not authenticated.
    let accessToken: String?
}

private struct WHAMUsageEnvelope: Decodable {
    struct PlanUsage: Decodable {
        let used: Int?
        let limit: Int?
        let resetAt: Date?
    }

    struct UsageContainer: Decodable {
        let codex: PlanUsage?
        // Some accounts surface usage under `o3` or `o4-mini` keys;
        // map the generic key for forward-compat.
        let o3: PlanUsage?
        let o4Mini: PlanUsage?

        enum CodingKeys: String, CodingKey {
            case codex
            case o3
            case o4Mini = "o4-mini"
        }
    }

    let usage: UsageContainer?

    func toQuotaWindows() -> [QuotaWindow] {
        // Prefer explicit codex bucket; fall back to o3 / o4-mini.
        let planUsage = usage?.codex ?? usage?.o3 ?? usage?.o4Mini

        guard let plan = planUsage,
              let used = plan.used,
              let limit = plan.limit,
              limit > 0 else {
            // Return a zero-usage placeholder so the row is visible.
            return [QuotaWindow(
                id: "codex-window",
                label: "Usage",
                usedPercentage: 0,
                resetAt: nil
            )]
        }

        let percentage = min(1.0, Double(used) / Double(limit))
        return [QuotaWindow(
            id: "codex-window",
            label: "Usage",
            usedPercentage: percentage,
            resetAt: plan.resetAt
        )]
    }
}
