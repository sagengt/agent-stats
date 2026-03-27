import Foundation

/// Fetches ChatGPT Codex usage from the WHAM API using credentials stored in
/// `CredentialStore`.
///
/// Credentials are populated via the `.importFromCLI` auth flow that reads
/// `~/.codex/auth.json` and encodes a `CodexCredential` into
/// `CredentialMaterial.providerMetadata`. This provider never reads auth files
/// directly during normal operation — it relies entirely on the stored credential.
struct CodexUsageProvider: QuotaWindowProvider, CredentialRequired {

    let account: AccountKey
    var serviceType: ServiceType { account.serviceType }
    let authMethod: AuthMethod = .importFromCLI

    private let credentialStore: CredentialStore
    private let apiClient: APIClient

    init(account: AccountKey, credentialStore: CredentialStore, apiClient: APIClient = .shared) {
        self.account = account
        self.credentialStore = credentialStore
        self.apiClient = apiClient
    }

    // MARK: - CredentialRequired

    func isConfigured() async -> Bool {
        guard let cred = await credentialStore.load(for: account),
              let _ = decodeMetadata(cred) else { return false }
        return true
    }

    // MARK: - QuotaWindowProvider

    func fetchQuotaWindows() async throws -> [QuotaWindow] {
        AppLogger.log("[CodexProvider] fetchQuotaWindows START")

        guard let cred = await credentialStore.load(for: account),
              let metadata = decodeMetadata(cred) else {
            throw ProviderError.notAuthenticated
        }

        var token = metadata.accessToken
        if metadata.isExpired {
            AppLogger.log("[CodexProvider] Token expired, refreshing...")
            token = try await refreshToken(metadata)
        }

        do {
            return try await fetchWHAM(token: token)
        } catch APIError.unauthorized {
            AppLogger.log("[CodexProvider] 401 received, attempting token refresh...")
            let refreshed = try await refreshToken(metadata)
            return try await fetchWHAM(token: refreshed)
        }
    }

    // MARK: - Private helpers

    private func decodeMetadata(_ cred: CredentialMaterial) -> CodexCredential? {
        guard let data = cred.providerMetadata else { return nil }
        return try? JSONDecoder().decode(CodexCredential.self, from: data)
    }

    private func refreshToken(_ metadata: CodexCredential) async throws -> String {
        guard let refreshToken = metadata.refreshToken else {
            AppLogger.log("[CodexProvider] No refresh_token available")
            throw ProviderError.notAuthenticated
        }

        let url = URL(string: "https://auth.openai.com/oauth/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": "pdlLIX2Y72MIl2rhLhTE9VV9bN905kBh"
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            AppLogger.log("[CodexProvider] Token refresh failed")
            throw ProviderError.notAuthenticated
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let newAccessToken = json["access_token"] as? String else {
            throw ProviderError.notAuthenticated
        }

        AppLogger.log("[CodexProvider] Token refreshed successfully")

        // Persist the refreshed credential
        let newRefreshToken = json["refresh_token"] as? String ?? refreshToken
        let expIn = json["expires_in"] as? Double
        let newExp = expIn.map { Date().addingTimeInterval($0) }
        let newCred = CodexCredential(
            accessToken: newAccessToken,
            refreshToken: newRefreshToken,
            chatgptAccountId: metadata.chatgptAccountId,
            email: metadata.email,
            expiresAt: newExp
        )
        let encoded = try? JSONEncoder().encode(newCred)
        let updated = CredentialMaterial(
            cookies: nil,
            authorizationHeader: nil,
            userAgent: nil,
            capturedAt: Date(),
            expiresAt: newExp,
            providerMetadata: encoded
        )
        await credentialStore.save(for: account, material: updated)

        return newAccessToken
    }

    private func fetchWHAM(token: String) async throws -> [QuotaWindow] {
        let headers: [String: String] = [
            "Authorization": "Bearer \(token)",
            "Accept": "application/json",
            "User-Agent": "AgentStats/1.0",
            "Referer": "https://chatgpt.com/"
        ]
        let url = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
        let data = try await apiClient.fetchRaw(from: url, headers: headers)
        let preview = String(data: data.prefix(500), encoding: .utf8) ?? ""
        AppLogger.log("[CodexProvider] WHAM response: \(preview)")
        return parseUsageResponse(data)
    }

    private func parseUsageResponse(_ data: Data) -> [QuotaWindow] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [QuotaWindow(id: "codex", label: "Usage", usedPercentage: 0, resetAt: nil)]
        }

        var windows: [QuotaWindow] = []

        // Format: { "rate_limit": { "primary_window": { "used_percent": N }, "secondary_window": { ... } } }
        if let rateLimit = json["rate_limit"] as? [String: Any] {
            if let primary = rateLimit["primary_window"] as? [String: Any] {
                let pct = (primary["used_percent"] as? Double ?? 0) / 100.0
                let resetSecs = primary["reset_after_seconds"] as? Double
                let resetAt = resetSecs.map { Date().addingTimeInterval($0) }
                let limitSecs = primary["limit_window_seconds"] as? Int ?? 18000
                let label = limitSecs == 18000 ? "5 Hour" : "\(limitSecs / 3600)h"
                windows.append(QuotaWindow(id: "5h", label: label, usedPercentage: pct, resetAt: resetAt))
            }
            if let secondary = rateLimit["secondary_window"] as? [String: Any] {
                let pct = (secondary["used_percent"] as? Double ?? 0) / 100.0
                let resetSecs = secondary["reset_after_seconds"] as? Double
                let resetAt = resetSecs.map { Date().addingTimeInterval($0) }
                let limitSecs = secondary["limit_window_seconds"] as? Int ?? 604800
                let label = limitSecs == 604800 ? "Weekly" : "\(limitSecs / 86400)d"
                windows.append(QuotaWindow(id: "weekly", label: label, usedPercentage: pct, resetAt: resetAt))
            }
        }

        // Fallback: top-level utilization fields
        if windows.isEmpty {
            for (key, val) in json {
                if let bucket = val as? [String: Any],
                   let util = bucket["utilization"] as? Double {
                    let pct = util > 1.0 ? util / 100.0 : util
                    windows.append(QuotaWindow(id: key, label: key.replacingOccurrences(of: "_", with: " ").capitalized, usedPercentage: pct, resetAt: nil))
                }
            }
        }

        if windows.isEmpty {
            windows.append(QuotaWindow(id: "codex", label: "Usage", usedPercentage: 0, resetAt: nil))
        }

        AppLogger.log("[CodexProvider] Parsed \(windows.count) window(s): \(windows.map { "\($0.id):\(Int($0.usedPercentage*100))%" }.joined(separator: ", "))")
        return windows
    }
}
