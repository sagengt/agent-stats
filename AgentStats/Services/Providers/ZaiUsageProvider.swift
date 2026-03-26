import Foundation

/// Fetches Z.ai Coding Plan quota windows from the Z.ai REST API.
///
/// Authentication uses an API key stored via `CredentialStore`. The key is
/// forwarded in the `Authorization` header as `Bearer <key>`.
///
/// Z.ai Coding Plan exposes rolling quota windows similar to Claude Code;
/// the provider maps the API response into `QuotaWindow` values that the
/// shared UI can render.
///
/// Implements `QuotaWindowProvider` and `CredentialRequired` (API key).
struct ZaiUsageProvider: QuotaWindowProvider, CredentialRequired {

    // MARK: Protocol requirements

    let account: AccountKey
    var serviceType: ServiceType { account.serviceType }
    let authMethod: AuthMethod = .apiKey

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

    // MARK: QuotaWindowProvider

    func fetchQuotaWindows() async throws -> [QuotaWindow] {
        guard let credential = await credentialStore.load(for: account) else {
            throw ProviderError.notAuthenticated
        }

        guard !credential.needsReauth else {
            throw ProviderError.notAuthenticated
        }

        guard let apiKey = extractAPIKey(from: credential) else {
            throw ProviderError.notAuthenticated
        }

        let headers = buildHeaders(apiKey: apiKey)
        let url = URL(string: "https://api.z.ai/v1/usage/quota")!

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

    private func buildHeaders(apiKey: String) -> [String: String] {
        [
            "Authorization": "Bearer \(apiKey)",
            "Accept":        "application/json",
            "Content-Type":  "application/json",
            "User-Agent":    "AgentStats/1.0 macOS",
        ]
    }

    private func extractAPIKey(from credential: CredentialMaterial) -> String? {
        if let header = credential.authorizationHeader, !header.isEmpty {
            return header.hasPrefix("Bearer ") ? String(header.dropFirst(7)) : header
        }
        return nil
    }

    /// Parses the Z.ai quota API response.
    ///
    /// Expected response shape (approximate):
    /// ```json
    /// {
    ///   "quota": {
    ///     "daily": {
    ///       "used_percentage": 0.35,
    ///       "reset_at": "2025-01-28T00:00:00Z"
    ///     },
    ///     "monthly": {
    ///       "used_percentage": 0.12,
    ///       "reset_at": "2025-02-01T00:00:00Z"
    ///     }
    ///   }
    /// }
    /// ```
    private func parseQuotaWindows(from data: Data) throws -> [QuotaWindow] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy  = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601

        do {
            let envelope = try decoder.decode(ZaiQuotaEnvelope.self, from: data)
            return envelope.toQuotaWindows()
        } catch {
            throw ProviderError.parseError(error.localizedDescription)
        }
    }
}

// MARK: - Response models (private)

private struct ZaiQuotaEnvelope: Decodable {
    struct WindowDetail: Decodable {
        let usedPercentage: Double?
        let used:           Int?
        let limit:          Int?
        let resetAt:        Date?
    }

    struct QuotaContainer: Decodable {
        let daily:   WindowDetail?
        let weekly:  WindowDetail?
        let monthly: WindowDetail?
    }

    let quota: QuotaContainer?

    func toQuotaWindows() -> [QuotaWindow] {
        var windows: [QuotaWindow] = []

        func percentage(from detail: WindowDetail?) -> Double {
            guard let d = detail else { return 0 }
            if let pct = d.usedPercentage {
                return max(0, min(1, pct))
            }
            if let used = d.used, let limit = d.limit, limit > 0 {
                return max(0, min(1, Double(used) / Double(limit)))
            }
            return 0
        }

        if let daily = quota?.daily {
            windows.append(QuotaWindow(
                id:             "zai-daily",
                label:          "Daily",
                usedPercentage: percentage(from: daily),
                resetAt:        daily.resetAt
            ))
        }

        if let weekly = quota?.weekly {
            windows.append(QuotaWindow(
                id:             "zai-weekly",
                label:          "Weekly",
                usedPercentage: percentage(from: weekly),
                resetAt:        weekly.resetAt
            ))
        }

        if let monthly = quota?.monthly {
            windows.append(QuotaWindow(
                id:             "zai-monthly",
                label:          "Monthly",
                usedPercentage: percentage(from: monthly),
                resetAt:        monthly.resetAt
            ))
        }

        // Provide a placeholder when the API returns no recognisable windows.
        if windows.isEmpty {
            windows.append(QuotaWindow(
                id:             "zai-unknown",
                label:          "Usage",
                usedPercentage: 0,
                resetAt:        nil
            ))
        }

        return windows
    }
}
