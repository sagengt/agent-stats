import Foundation

/// Fetches Claude Code quota consumption from the Anthropic web API using
/// session cookies captured via the OAuth WebView login flow.
///
/// Implements `QuotaWindowProvider` (5-hour and weekly windows) and
/// `CredentialRequired` (OAuth via claude.ai).
struct ClaudeUsageProvider: QuotaWindowProvider, CredentialRequired {

    // MARK: Protocol requirements

    let account: AccountKey
    var serviceType: ServiceType { account.serviceType }
    let authMethod: AuthMethod = .oauthWebView(loginURL: URL(string: "https://claude.ai/login")!)

    // MARK: Dependencies

    private let credentialStore: CredentialStore
    private let apiClient: APIClient

    // MARK: Init

    init(account: AccountKey, credentialStore: CredentialStore, apiClient: APIClient = .shared) {
        self.account = account
        self.credentialStore = credentialStore
        self.apiClient = apiClient
    }

    // MARK: UsageProviderProtocol

    func isConfigured() async -> Bool {
        guard let credential = await credentialStore.load(for: account) else {
            AppLogger.log("[ClaudeProvider] isConfigured: NO credential found for \(account.accountId.prefix(8))")
            return false
        }
        let expired = credential.isExpired
        let needsReauth = credential.needsReauth
        if expired || needsReauth {
            AppLogger.log("[ClaudeProvider] isConfigured: credential exists but expired=\(expired) needsReauth=\(needsReauth)")
        }
        return !expired && !needsReauth
    }

    // MARK: QuotaWindowProvider

    func fetchQuotaWindows() async throws -> [QuotaWindow] {
        guard let credential = await credentialStore.load(for: account) else {
            throw ProviderError.notAuthenticated
        }

        guard !credential.isExpired else {
            throw ProviderError.notAuthenticated
        }

        let headers = buildHeaders(from: credential)

        // Step 1: Discover the organization ID.
        let orgId: String
        do {
            orgId = try await resolveOrgId(credential: credential, headers: headers)
            AppLogger.log("[ClaudeProvider] Resolved orgId: \(orgId)")
        } catch {
            AppLogger.log("[ClaudeProvider] Failed to resolve orgId: \(error)")
            throw error
        }

        // Step 2: Fetch usage for the resolved organization.
        let url = URL(string: "https://claude.ai/api/organizations/\(orgId)/usage")!
        AppLogger.log("[ClaudeProvider] Fetching usage from: \(url)")
        do {
            let raw = try await apiClient.fetchRaw(from: url, headers: headers)
            let preview = String(data: raw.prefix(2000), encoding: .utf8) ?? "(binary \(raw.count) bytes)"
            AppLogger.log("[ClaudeProvider] Raw API response (\(raw.count) bytes):\n\(preview)")
            return try parseQuotaWindows(from: raw)
        } catch APIError.unauthorized {
            AppLogger.log("[ClaudeProvider] ERROR: Unauthorized (401/403)")
            throw ProviderError.notAuthenticated
        } catch let providerError as ProviderError {
            AppLogger.log("[ClaudeProvider] ERROR: \(providerError)")
            throw providerError
        } catch {
            AppLogger.log("[ClaudeProvider] ERROR: \(error)")
            throw ProviderError.fetchFailed(error.localizedDescription)
        }
    }

    /// Resolves the Claude organization ID from cookies or the API.
    private func resolveOrgId(credential: CredentialMaterial, headers: [String: String]) async throws -> String {
        // 1. Check the `lastActiveOrg` cookie (set by claude.ai).
        if let cookies = credential.cookies {
            for cookie in cookies {
                if cookie.name == "lastActiveOrg" && !cookie.value.isEmpty {
                    return cookie.value
                }
            }
        }

        // 2. Fall back to the organizations list API.
        let orgsURL = URL(string: "https://claude.ai/api/organizations")!
        do {
            let data = try await apiClient.fetchRaw(from: orgsURL, headers: headers)
            let orgs = try JSONDecoder().decode([ClaudeOrganization].self, from: data)
            // Prefer the personal/individual org, fall back to first available.
            if let personal = orgs.first(where: { $0.name?.lowercased().contains("personal") == true }) {
                return personal.uuid
            }
            if let first = orgs.first {
                return first.uuid
            }
        } catch {
            // Ignore — we'll throw below.
        }

        throw ProviderError.fetchFailed("Could not determine Claude organization ID")
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
        do {
            return try ClaudeUsageParser.parse(from: data)
        } catch {
            throw ProviderError.parseError(error.localizedDescription)
        }
    }
}

// MARK: - Response models (private)

private struct ClaudeOrganization: Decodable {
    let uuid: String
    let name: String?
}

/// Flexible parser that handles multiple known Claude API response shapes.
private enum ClaudeUsageParser {
    static func parse(from data: Data) throws -> [QuotaWindow] {
        // Try multiple known response formats.
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        var windows: [QuotaWindow] = []

        // Format 1: Claude.ai actual format
        // { "five_hour": {"utilization": 29.0, "resets_at": "..."}, "seven_day": {"utilization": 48.0, ...} }
        let windowMappings: [(keys: [String], id: String, label: String)] = [
            (["five_hour", "five_hour_usage", "fiveHour"], "5h", "5 Hour"),
            (["seven_day", "seven_day_usage", "sevenDay", "weekly", "weekly_usage"], "weekly", "Weekly"),
            (["seven_day_sonnet", "sevenDaySonnet"], "weekly_sonnet", "Weekly (Sonnet)"),
            (["seven_day_opus", "sevenDayOpus"], "weekly_opus", "Weekly (Opus)"),
            (["daily", "daily_usage"], "daily", "Daily"),
        ]

        for mapping in windowMappings {
            if let pct = extractPercentage(from: json, keys: mapping.keys) {
                let resetAt = extractDate(from: json, keys: mapping.keys.flatMap { [$0] })
                    ?? extractNestedDate(from: json, keys: mapping.keys)
                windows.append(makeWindow(id: mapping.id, label: mapping.label, percentage: pct, resetAt: resetAt))
            }
        }

        // Format 2: Nested under "quota" object
        if let quota = json["quota"] as? [String: Any] {
            for (key, value) in quota {
                if let detail = value as? [String: Any],
                   let pct = detail["used_percentage"] as? Double ?? detail["usedPercentage"] as? Double {
                    let resetStr = detail["reset_at"] as? String ?? detail["resetAt"] as? String
                    let resetDate = resetStr.flatMap { ISO8601DateFormatter().date(from: $0) }
                    let windowId = key.replacingOccurrences(of: "_", with: "")
                    let label = key.replacingOccurrences(of: "_", with: " ").capitalized
                    if !windows.contains(where: { $0.id == windowId }) {
                        windows.append(makeWindow(id: windowId, label: label, percentage: pct, resetAt: resetDate))
                    }
                }
            }
        }

        // Format 3: Array of rate limit windows
        if let limits = json["rate_limits"] as? [[String: Any]] ?? json["rateLimits"] as? [[String: Any]] {
            for limit in limits {
                if let name = limit["name"] as? String ?? limit["window"] as? String,
                   let used = limit["used"] as? Double,
                   let total = limit["total"] as? Double, total > 0 {
                    let pct = used / total
                    let resetStr = limit["reset_at"] as? String ?? limit["resetAt"] as? String ?? limit["resetsAt"] as? String
                    let resetDate = resetStr.flatMap { ISO8601DateFormatter().date(from: $0) }
                    let windowId = name.lowercased().replacingOccurrences(of: " ", with: "")
                    if !windows.contains(where: { $0.id == windowId }) {
                        windows.append(makeWindow(id: windowId, label: name, percentage: pct, resetAt: resetDate))
                    }
                }
            }
        }

        if windows.isEmpty {
            // Log the raw response for debugging.
            let preview = String(data: data.prefix(500), encoding: .utf8) ?? "(binary)"
            AppLogger.log("[ClaudeUsageProvider] Unknown response format: \(preview)")
            windows.append(QuotaWindow(id: "unknown", label: "Usage", usedPercentage: 0, resetAt: nil))
        }

        return windows
    }

    private static func extractPercentage(from json: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let val = json[key] as? Double { return val }
            if let nested = json[key] as? [String: Any] {
                // Try all known field names for percentage/utilization
                if let pct = nested["used_percentage"] as? Double
                    ?? nested["usedPercentage"] as? Double
                    ?? nested["utilization"] as? Double {
                    // `utilization` from Claude API is 0-100, normalize to 0-1
                    return pct > 1.0 ? pct / 100.0 : pct
                }
            }
        }
        return nil
    }

    private static func extractDate(from json: [String: Any], keys: [String]) -> Date? {
        for key in keys {
            if let str = json[key] as? String {
                return parseDate(str)
            }
        }
        return nil
    }

    /// Extract date from nested object like {"five_hour": {"resets_at": "..."}}
    private static func extractNestedDate(from json: [String: Any], keys: [String]) -> Date? {
        for key in keys {
            if let nested = json[key] as? [String: Any] {
                let dateKeys = ["resets_at", "resetsAt", "reset_at", "resetAt"]
                for dk in dateKeys {
                    if let str = nested[dk] as? String {
                        return parseDate(str)
                    }
                }
            }
        }
        return nil
    }

    private static func parseDate(_ string: String) -> Date? {
        // Try ISO8601 with fractional seconds and timezone
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        // Fallback without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    private static func makeWindow(id: String, label: String, percentage: Double, resetAt: Date?) -> QuotaWindow {
        QuotaWindow(id: id, label: label, usedPercentage: max(0, min(1, percentage)), resetAt: resetAt)
    }
}
