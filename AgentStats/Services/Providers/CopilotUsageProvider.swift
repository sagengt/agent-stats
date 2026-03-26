import Foundation

/// Fetches GitHub Copilot token-usage metrics via the GitHub REST API.
///
/// Authentication uses a Personal Access Token (PAT) with the
/// `copilot` scope. The PAT is stored in the shared `CredentialStore`
/// and forwarded as a `Bearer` token in the `Authorization` header.
///
/// Endpoint used (organization-level, requires admin PAT):
///   GET https://api.github.com/orgs/{org}/copilot/usage
///
/// For individual users without an org the provider attempts:
///   GET https://api.github.com/copilot/usage
///
/// Because Copilot's individual-user usage API is in beta and may not be
/// available for all accounts, the provider gracefully falls back to a
/// zero-usage summary rather than surfacing an error in the UI.
///
/// Implements `TokenUsageProvider` and `CredentialRequired` (PAT).
struct CopilotUsageProvider: TokenUsageProvider, CredentialRequired {

    // MARK: Protocol requirements

    let account: AccountKey
    var serviceType: ServiceType { account.serviceType }
    let authMethod: AuthMethod = .personalAccessToken

    // MARK: Dependencies

    private let credentialStore: CredentialStore
    private let apiClient: APIClient

    // MARK: Init

    init(
        account: AccountKey,
        credentialStore: CredentialStore,
        apiClient: APIClient = .shared
    ) {
        self.account = account
        self.credentialStore = credentialStore
        self.apiClient = apiClient
    }

    // MARK: UsageProviderProtocol

    func isConfigured() async -> Bool {
        guard let credential = await credentialStore.load(for: account) else { return false }
        return !credential.needsReauth
    }

    // MARK: TokenUsageProvider

    func fetchTokenUsage() async throws -> TokenUsageSummary {
        guard let credential = await credentialStore.load(for: account) else {
            throw ProviderError.notAuthenticated
        }

        guard !credential.needsReauth else {
            throw ProviderError.notAuthenticated
        }

        guard let pat = extractPAT(from: credential) else {
            throw ProviderError.notAuthenticated
        }

        let headers = buildHeaders(pat: pat)

        // Try the individual-user usage endpoint.
        let usageURL = URL(string: "https://api.github.com/copilot/usage")!
        do {
            let raw = try await apiClient.fetchRaw(from: usageURL, headers: headers)
            return try parseUsage(from: raw)
        } catch APIError.unauthorized {
            throw ProviderError.notAuthenticated
        } catch APIError.httpError(let code, _) where code == 404 {
            // Endpoint not available for this account type; return zero summary.
            return zeroSummary()
        } catch let providerError as ProviderError {
            throw providerError
        } catch {
            throw ProviderError.fetchFailed(error.localizedDescription)
        }
    }

    // MARK: Private helpers

    private func buildHeaders(pat: String) -> [String: String] {
        [
            "Authorization": "Bearer \(pat)",
            "Accept":        "application/vnd.github+json",
            "User-Agent":    "AgentStats/1.0 macOS",
            "X-GitHub-Api-Version": "2022-11-28",
        ]
    }

    private func extractPAT(from credential: CredentialMaterial) -> String? {
        if let header = credential.authorizationHeader, !header.isEmpty {
            return header.hasPrefix("Bearer ") ? String(header.dropFirst(7)) : header
        }
        return nil
    }

    /// Parses the GitHub Copilot usage API response.
    ///
    /// The individual-user endpoint returns an array of daily breakdown objects:
    /// ```json
    /// [
    ///   {
    ///     "day": "2025-01-27",
    ///     "total_suggestions_count": 120,
    ///     "total_acceptances_count": 80,
    ///     "total_lines_suggested": 350,
    ///     "total_lines_accepted": 200,
    ///     "total_active_users": 1,
    ///     "breakdown": [ ... ]
    ///   }
    /// ]
    /// ```
    /// Token counts are not directly exposed; `total_suggestions_count` and
    /// `total_acceptances_count` are used as a proxy metric (mapped to
    /// inputTokens and outputTokens respectively for display purposes).
    private func parseUsage(from data: Data) throws -> TokenUsageSummary {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601

        do {
            let entries = try decoder.decode([CopilotDailyUsage].self, from: data)
            return aggregate(entries: entries)
        } catch {
            throw ProviderError.parseError(error.localizedDescription)
        }
    }

    private func aggregate(entries: [CopilotDailyUsage]) -> TokenUsageSummary {
        // Sum across all returned days (typically the current billing cycle).
        let totalSuggestions = entries.reduce(0) { $0 + ($1.totalSuggestionsCount ?? 0) }
        let totalAcceptances  = entries.reduce(0) { $0 + ($1.totalAcceptancesCount  ?? 0) }

        return TokenUsageSummary(
            totalTokens:  totalSuggestions + totalAcceptances,
            inputTokens:  totalSuggestions,   // suggestions sent to user ≈ input
            outputTokens: totalAcceptances,   // accepted completions ≈ output
            costUSD:      nil,
            period:       .thisMonth
        )
    }

    private func zeroSummary() -> TokenUsageSummary {
        TokenUsageSummary(
            totalTokens:  0,
            inputTokens:  0,
            outputTokens: 0,
            costUSD:      nil,
            period:       .thisMonth
        )
    }
}

// MARK: - Response models (private)

private struct CopilotDailyUsage: Decodable {
    let day: String?
    let totalSuggestionsCount: Int?
    let totalAcceptancesCount:  Int?
    let totalLinesSuggested:   Int?
    let totalLinesAccepted:    Int?
    let totalActiveUsers:      Int?
}
