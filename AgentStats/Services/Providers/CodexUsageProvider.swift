import Foundation

/// Fetches ChatGPT Codex usage from local session log files.
///
/// Uses the AgentBar approach: reads `~/.codex/sessions/` JSONL files
/// to compute token usage and rate limit status locally, without
/// requiring WebView JavaScript injection or API calls.
///
/// Falls back to the ChatGPT web API via stored cookies if local files
/// are not available (e.g. user doesn't have the Codex CLI installed).
struct CodexUsageProvider: QuotaWindowProvider, CredentialRequired {

    let account: AccountKey
    var serviceType: ServiceType { account.serviceType }
    let authMethod: AuthMethod = .oauthWebView(loginURL: URL(string: "https://chatgpt.com")!)

    private let credentialStore: CredentialStore
    private let apiClient: APIClient

    init(account: AccountKey, credentialStore: CredentialStore, apiClient: APIClient = .shared) {
        self.account = account
        self.credentialStore = credentialStore
        self.apiClient = apiClient
    }

    func isConfigured() async -> Bool {
        // Configured if we have local auth.json OR local session files OR stored credentials
        if readCodexAuthToken() != nil { return true }
        if hasLocalSessionFiles() { return true }
        guard let credential = await credentialStore.load(for: account) else { return false }
        return !credential.isExpired && !credential.needsReauth
    }

    func fetchQuotaWindows() async throws -> [QuotaWindow] {
        AppLogger.log("[CodexProvider] fetchQuotaWindows START")

        // Strategy 1: Read access_token from ~/.codex/auth.json (most reliable)
        if let token = readCodexAuthToken() {
            AppLogger.log("[CodexProvider] Got token from ~/.codex/auth.json")
            do {
                let windows = try await fetchUsageWithToken(token)
                if !windows.isEmpty { return windows }
            } catch {
                AppLogger.log("[CodexProvider] API fetch with local token failed: \(error)")
            }
        }

        // Strategy 2: Read local session files for token stats
        if let windows = try? readLocalSessionFiles(), !windows.isEmpty {
            AppLogger.log("[CodexProvider] Got \(windows.count) window(s) from local files")
            return windows
        }

        // Strategy 3: Use stored cookies to call ChatGPT API directly
        guard let credential = await credentialStore.load(for: account) else {
            throw ProviderError.notAuthenticated
        }

        let windows = try await fetchViaAPI(credential: credential)
        return windows
    }

    /// Reads the access token from `~/.codex/auth.json`
    private func readCodexAuthToken() -> String? {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/auth.json").path
        guard let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = json["tokens"] as? [String: Any],
              let token = tokens["access_token"] as? String,
              !token.isEmpty else {
            return nil
        }
        return token
    }

    /// Fetches usage from ChatGPT WHAM API using a bearer token
    private func fetchUsageWithToken(_ token: String) async throws -> [QuotaWindow] {
        var headers: [String: String] = [
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

    // MARK: - Strategy 1: Local session files

    private func hasLocalSessionFiles() -> Bool {
        let paths = codexSessionPaths()
        return paths.contains { FileManager.default.fileExists(atPath: $0) }
    }

    private func codexSessionPaths() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "\(home)/.codex/sessions",
            "\(home)/.codex",
            "\(home)/.config/codex/sessions"
        ]
    }

    private func readLocalSessionFiles() throws -> [QuotaWindow] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path

        // Look for session JSONL files
        let sessionDirs = [
            "\(home)/.codex/sessions",
            "\(home)/.codex"
        ]

        var totalInputTokens = 0
        var totalOutputTokens = 0
        var sessionCount = 0
        let today = Calendar.current.startOfDay(for: Date())

        for dir in sessionDirs {
            guard fm.fileExists(atPath: dir) else { continue }

            let files: [String]
            do {
                files = try fm.contentsOfDirectory(atPath: dir)
            } catch { continue }

            for file in files where file.hasSuffix(".jsonl") || file.hasSuffix(".json") {
                let path = "\(dir)/\(file)"

                // Only count today's files
                if let attrs = try? fm.attributesOfItem(atPath: path),
                   let modDate = attrs[.modificationDate] as? Date,
                   modDate >= today {

                    if let content = try? String(contentsOfFile: path, encoding: .utf8) {
                        let lines = content.components(separatedBy: .newlines)
                        for line in lines where !line.isEmpty {
                            if let data = line.data(using: .utf8),
                               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                                // Count tokens from usage entries
                                if let usage = json["usage"] as? [String: Any] {
                                    totalInputTokens += usage["input_tokens"] as? Int ?? usage["prompt_tokens"] as? Int ?? 0
                                    totalOutputTokens += usage["completion_tokens"] as? Int ?? usage["output_tokens"] as? Int ?? 0
                                }
                                // Count sessions
                                if json["type"] as? String == "session_start" || json["event"] as? String == "start" {
                                    sessionCount += 1
                                }
                            }
                        }
                    }
                }
            }
        }

        let totalTokens = totalInputTokens + totalOutputTokens
        AppLogger.log("[CodexProvider] Local files: \(totalTokens) tokens (\(totalInputTokens) in, \(totalOutputTokens) out), \(sessionCount) session(s)")

        if totalTokens > 0 || sessionCount > 0 {
            // Estimate usage based on typical Codex Plus limits
            // ChatGPT Plus: ~80 messages/3h window, Pro: unlimited
            let estimatedLimit = 500_000  // rough daily token limit
            let pct = min(1.0, Double(totalTokens) / Double(estimatedLimit))
            return [
                QuotaWindow(
                    id: "daily",
                    label: "Today (\(formatTokens(totalTokens)) tokens)",
                    usedPercentage: pct,
                    resetAt: Calendar.current.date(byAdding: .day, value: 1, to: today)
                )
            ]
        }

        return []
    }

    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 1_000 { return String(format: "%.1fK", Double(count) / 1_000) }
        return "\(count)"
    }

    // MARK: - Strategy 2: API via cookies

    private func fetchViaAPI(credential: CredentialMaterial) async throws -> [QuotaWindow] {
        AppLogger.log("[CodexProvider] Trying API with cookies...")

        var headers: [String: String] = [:]
        let cookieHeader = credential.httpCookies()
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")
        if !cookieHeader.isEmpty { headers["Cookie"] = cookieHeader }
        if let ua = credential.userAgent { headers["User-Agent"] = ua }
        else { headers["User-Agent"] = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15" }
        headers["Accept"] = "application/json"
        headers["Referer"] = "https://chatgpt.com/"

        // Try to get session token from the session endpoint
        let sessionEndpoints = [
            "https://chatgpt.com/api/auth/session",
            "https://chatgpt.com/backend-api/auth/session"
        ]

        var accessToken: String?
        for endpoint in sessionEndpoints {
            do {
                let data = try await apiClient.fetchRaw(from: URL(string: endpoint)!, headers: headers)
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    accessToken = json["accessToken"] as? String ?? json["access_token"] as? String
                    if accessToken != nil {
                        AppLogger.log("[CodexProvider] Got token from \(endpoint)")
                        break
                    }
                }
            } catch {
                AppLogger.log("[CodexProvider] \(endpoint) failed: \(error.localizedDescription)")
            }
        }

        // If we got a token, fetch usage
        if let token = accessToken {
            var usageHeaders = headers
            usageHeaders["Authorization"] = "Bearer \(token)"
            do {
                let data = try await apiClient.fetchRaw(from: URL(string: "https://chatgpt.com/backend-api/wham/usage")!, headers: usageHeaders)
                let preview = String(data: data.prefix(300), encoding: .utf8) ?? ""
                AppLogger.log("[CodexProvider] Usage response: \(preview)")
                return parseUsageResponse(data)
            } catch {
                AppLogger.log("[CodexProvider] Usage fetch failed: \(error)")
            }
        }

        // No token available — return placeholder
        AppLogger.log("[CodexProvider] No access token obtained")
        return [QuotaWindow(id: "codex", label: "Usage (sign in required)", usedPercentage: 0, resetAt: nil)]
    }

    private func parseUsageResponse(_ data: Data) -> [QuotaWindow] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [QuotaWindow(id: "codex", label: "Usage", usedPercentage: 0, resetAt: nil)]
        }

        var windows: [QuotaWindow] = []
        let isoFormatter = ISO8601DateFormatter()
        let isoFractional = ISO8601DateFormatter()
        isoFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        for (key, val) in json {
            if let bucket = val as? [String: Any],
               let util = bucket["utilization"] as? Double {
                let pct = util > 1.0 ? util / 100.0 : util
                let resetStr = bucket["resets_at"] as? String ?? bucket["reset_at"] as? String
                let resetDate = resetStr.flatMap { isoFractional.date(from: $0) ?? isoFormatter.date(from: $0) }
                windows.append(QuotaWindow(
                    id: key,
                    label: key.replacingOccurrences(of: "_", with: " ").capitalized,
                    usedPercentage: pct,
                    resetAt: resetDate
                ))
            }
        }

        if windows.isEmpty {
            windows.append(QuotaWindow(id: "codex", label: "Usage", usedPercentage: 0, resetAt: nil))
        }
        return windows
    }
}
