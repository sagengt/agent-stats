import Foundation

/// Fetches Z.ai Coding Plan usage from the Z.ai API.
///
/// Authentication: API key (Bearer token)
/// Endpoint: GET https://api.z.ai/api/monitor/usage/quota/limit
///
/// See docs/zai-integration-spec.md for details.
struct ZaiUsageProvider: QuotaWindowProvider, CredentialRequired {

    let account: AccountKey
    var serviceType: ServiceType { account.serviceType }
    let authMethod: AuthMethod = .apiKey

    private let credentialStore: CredentialStore
    private let apiClient: APIClient

    init(account: AccountKey, credentialStore: CredentialStore, apiClient: APIClient = .shared) {
        self.account = account
        self.credentialStore = credentialStore
        self.apiClient = apiClient
    }

    func isConfigured() async -> Bool {
        guard let cred = await credentialStore.load(for: account) else { return false }
        return cred.authorizationHeader != nil
    }

    func fetchQuotaWindows() async throws -> [QuotaWindow] {
        AppLogger.log("[ZaiProvider] fetchQuotaWindows START")

        guard let cred = await credentialStore.load(for: account),
              let apiKey = cred.authorizationHeader else {
            throw ProviderError.notAuthenticated
        }

        let key = apiKey.hasPrefix("Bearer ") ? String(apiKey.dropFirst(7)) : apiKey
        let url = URL(string: "https://api.z.ai/api/monitor/usage/quota/limit")!

        // Try Bearer format first
        var headers: [String: String] = [
            "Authorization": "Bearer \(key)",
            "Accept": "application/json",
            "Accept-Language": "en-US,en"
        ]

        do {
            let data = try await apiClient.fetchRaw(from: url, headers: headers)
            let preview = String(data: data.prefix(500), encoding: .utf8) ?? ""
            AppLogger.log("[ZaiProvider] Response: \(preview)")
            return parseResponse(data)
        } catch APIError.unauthorized {
            // Retry with raw key
            AppLogger.log("[ZaiProvider] Bearer failed, retrying with raw key")
            headers["Authorization"] = key
            let data = try await apiClient.fetchRaw(from: url, headers: headers)
            return parseResponse(data)
        }
    }

    private func parseResponse(_ data: Data) -> [QuotaWindow] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = json["data"] as? [String: Any],
              let limits = dataObj["limits"] as? [[String: Any]] else {
            AppLogger.log("[ZaiProvider] Failed to parse response")
            return [QuotaWindow(id: "zai", label: "Usage", usedPercentage: 0, resetAt: nil)]
        }

        var windows: [QuotaWindow] = []

        for limit in limits {
            let type = limit["type"] as? String ?? "unknown"
            let nextReset = limit["nextResetTime"] as? Double
            let resetAt = nextReset.map { Date(timeIntervalSince1970: $0 / 1000.0) }

            switch type {
            case "TOKENS_LIMIT":
                let pct = (limit["percentage"] as? Double ?? 0) / 100.0
                windows.append(QuotaWindow(id: "5h", label: "5 Hour", usedPercentage: pct, resetAt: resetAt))

            case "TIME_LIMIT":
                let usage = limit["usage"] as? Double ?? 0
                let current = limit["currentValue"] as? Double ?? 0
                let pct = usage > 0 ? min(1.0, current / usage) : 0
                windows.append(QuotaWindow(id: "monthly", label: "Monthly", usedPercentage: pct, resetAt: resetAt))

            default:
                if let pct = limit["percentage"] as? Double {
                    windows.append(QuotaWindow(id: type.lowercased(), label: type, usedPercentage: pct / 100.0, resetAt: resetAt))
                }
            }
        }

        if let level = dataObj["level"] as? String {
            AppLogger.log("[ZaiProvider] Plan level: \(level)")
        }

        if windows.isEmpty {
            windows.append(QuotaWindow(id: "zai", label: "Connected", usedPercentage: 0, resetAt: nil))
        }

        AppLogger.log("[ZaiProvider] Parsed \(windows.count) window(s)")
        return windows
    }
}
