import Foundation

/// Fetches Claude Code quota consumption from the Anthropic web API using
/// session cookies captured via the OAuth WebView login flow.
///
/// Implements `QuotaWindowProvider` (5-hour and weekly windows) and
/// `CredentialRequired` (OAuth via claude.ai).
struct ClaudeUsageProvider: QuotaWindowProvider, CredentialRequired {

    // MARK: Protocol requirements

    let serviceType: ServiceType = .claude
    let authMethod: AuthMethod = .oauthWebView(loginURL: URL(string: "https://claude.ai")!)

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
        guard let credential = await credentialStore.load(for: .claude) else { return false }
        return !credential.isExpired && !credential.needsReauth
    }

    // MARK: QuotaWindowProvider

    func fetchQuotaWindows() async throws -> [QuotaWindow] {
        guard let credential = await credentialStore.load(for: .claude) else {
            throw ProviderError.notAuthenticated
        }

        guard !credential.isExpired else {
            throw ProviderError.notAuthenticated
        }

        let headers = buildHeaders(from: credential)

        // Attempt to fetch live data from the Claude usage endpoint.
        // The organisation ID is embedded in the first-party cookies; the
        // endpoint falls back to a user-scoped path when no org is resolved.
        let url = URL(string: "https://claude.ai/api/usage")!
        do {
            let raw = try await apiClient.fetchRaw(from: url, headers: headers)
            return try parseQuotaWindows(from: raw)
        } catch APIError.unauthorized {
            throw ProviderError.notAuthenticated
        } catch let providerError as ProviderError {
            throw providerError
        } catch {
            throw ProviderError.fetchFailed(error.localizedDescription)
        }
    }

    // MARK: Private helpers

    private func buildHeaders(from credential: CredentialMaterial) -> [String: String] {
        var headers: [String: String] = [:]

        // Reconstruct the Cookie header from stored DTOs.
        let cookieHeader = credential.httpCookies()
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")
        if !cookieHeader.isEmpty {
            headers["Cookie"] = cookieHeader
        }

        if let authHeader = credential.authorizationHeader {
            headers["Authorization"] = authHeader
        }

        if let userAgent = credential.userAgent {
            headers["User-Agent"] = userAgent
        } else {
            headers["User-Agent"] = "AgentStats/1.0 macOS"
        }

        headers["Accept"] = "application/json"
        headers["Content-Type"] = "application/json"

        return headers
    }

    private func parseQuotaWindows(from data: Data) throws -> [QuotaWindow] {
        // Claude usage API response shape (approximate):
        // {
        //   "quota": {
        //     "five_hour": { "used_percentage": 0.42, "reset_at": "2025-01-27T15:00:00Z" },
        //     "weekly":    { "used_percentage": 0.18, "reset_at": "2025-02-01T00:00:00Z" }
        //   }
        // }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601

        do {
            let envelope = try decoder.decode(ClaudeUsageEnvelope.self, from: data)
            return envelope.toQuotaWindows()
        } catch {
            throw ProviderError.parseError(error.localizedDescription)
        }
    }
}

// MARK: - Response models (private)

private struct ClaudeUsageEnvelope: Decodable {
    struct WindowDetail: Decodable {
        let usedPercentage: Double
        let resetAt: Date?
    }

    struct QuotaContainer: Decodable {
        let fiveHour: WindowDetail?
        let weekly: WindowDetail?
    }

    let quota: QuotaContainer?

    func toQuotaWindows() -> [QuotaWindow] {
        var windows: [QuotaWindow] = []

        if let fiveHour = quota?.fiveHour {
            windows.append(QuotaWindow(
                id: "5h",
                label: "5 Hour",
                usedPercentage: max(0, min(1, fiveHour.usedPercentage)),
                resetAt: fiveHour.resetAt
            ))
        }

        if let weekly = quota?.weekly {
            windows.append(QuotaWindow(
                id: "weekly",
                label: "Weekly",
                usedPercentage: max(0, min(1, weekly.usedPercentage)),
                resetAt: weekly.resetAt
            ))
        }

        // Provide placeholder windows when the API returns no usable data so
        // the UI can still render the service row.
        if windows.isEmpty {
            windows.append(QuotaWindow(
                id: "unknown",
                label: "Usage",
                usedPercentage: 0,
                resetAt: nil
            ))
        }

        return windows
    }
}
