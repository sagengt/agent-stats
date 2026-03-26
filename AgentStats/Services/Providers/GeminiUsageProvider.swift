import Foundation

/// Fetches Google Gemini CLI usage data.
///
/// Authentication: Reads OAuth token from ~/.gemini/oauth_creds.json
/// or macOS Keychain (gemini-cli-oauth service).
/// Account info: Reads email from ~/.gemini/google_accounts.json.
/// Quota: Calls https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota
///
/// See docs/gemini-integration-spec.md for details.
struct GeminiUsageProvider: QuotaWindowProvider, CredentialRequired {

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
        if readLocalAccessToken() != nil { return true }
        guard let cred = await credentialStore.load(for: account) else { return false }
        return !cred.needsReauth
    }

    func fetchQuotaWindows() async throws -> [QuotaWindow] {
        AppLogger.log("[GeminiProvider] fetchQuotaWindows START")

        // Strategy 1: Use local Gemini CLI OAuth token
        if let token = readLocalAccessToken() {
            AppLogger.log("[GeminiProvider] Using local OAuth token")
            do {
                return try await fetchQuotaWithToken(token)
            } catch {
                AppLogger.log("[GeminiProvider] Quota failed: \(error), trying refresh...")
                if let refreshed = try? await refreshToken() {
                    return try await fetchQuotaWithToken(refreshed)
                }
            }
        }

        // Strategy 2: Use stored API key
        if let cred = await credentialStore.load(for: account),
           let apiKey = cred.authorizationHeader {
            let key = apiKey.replacingOccurrences(of: "Bearer ", with: "")
            return try await fetchQuotaWithToken(key)
        }

        throw ProviderError.notAuthenticated
    }

    // MARK: - Local token

    private func readLocalAccessToken() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let path = home.appendingPathComponent(".gemini/oauth_creds.json")
        guard let data = try? Data(contentsOf: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String, !token.isEmpty else { return nil }
        if let expiry = json["expiry_date"] as? Double {
            let expiryDate = Date(timeIntervalSince1970: expiry / 1000.0)
            if expiryDate <= Date() {
                AppLogger.log("[GeminiProvider] Token expired")
                return nil
            }
        }
        return token
    }

    private func readRefreshToken() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let path = home.appendingPathComponent(".gemini/oauth_creds.json")
        guard let data = try? Data(contentsOf: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["refresh_token"] as? String
    }

    private func refreshToken() async throws -> String? {
        guard let refreshToken = readRefreshToken() else { return nil }

        // Read client credentials from the Gemini CLI's own oauth_creds.json or environment
        let home = FileManager.default.homeDirectoryForCurrentUser
        let oauthPath = home.appendingPathComponent(".gemini/oauth_creds.json")
        guard let oauthData = try? Data(contentsOf: oauthPath),
              let oauthJson = try? JSONSerialization.jsonObject(with: oauthData) as? [String: Any] else {
            return nil
        }

        // Read client credentials from the Gemini CLI's installed source code.
        // These are public "installed application" credentials distributed with the CLI.
        let (clientId, clientSecret) = readGeminiClientCredentials()
        guard !clientId.isEmpty, !clientSecret.isEmpty else {
            AppLogger.log("[GeminiProvider] No client credentials for token refresh")
            return nil
        }

        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = "grant_type=refresh_token&refresh_token=\(refreshToken)&client_id=\(clientId)&client_secret=\(clientSecret)".data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let newToken = json["access_token"] as? String else { return nil }

        // Update local file
        let oauthFile = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".gemini/oauth_creds.json")
        let path = oauthFile
        if var creds = (try? Data(contentsOf: path)).flatMap({ try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }) {
            creds["access_token"] = newToken
            creds["expiry_date"] = (Date().timeIntervalSince1970 + Double(json["expires_in"] as? Int ?? 3600)) * 1000.0
            if let updated = try? JSONSerialization.data(withJSONObject: creds, options: [.prettyPrinted]) {
                try? updated.write(to: path)
            }
        }
        AppLogger.log("[GeminiProvider] Token refreshed")
        return newToken
    }

    // MARK: - Quota API

    private func fetchQuotaWithToken(_ token: String) async throws -> [QuotaWindow] {
        let url = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota")!
        let headers = ["Authorization": "Bearer \(token)", "Content-Type": "application/json", "Accept": "application/json"]

        let data = try await apiClient.fetchRaw(from: url, headers: headers)
        let preview = String(data: data.prefix(500), encoding: .utf8) ?? ""
        AppLogger.log("[GeminiProvider] Quota response: \(preview)")
        return parseQuotaResponse(data)
    }

    private func parseQuotaResponse(_ data: Data) -> [QuotaWindow] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [QuotaWindow(id: "gemini", label: "Usage", usedPercentage: 0, resetAt: nil)]
        }

        var windows: [QuotaWindow] = []

        if let quotas = json["quotas"] as? [[String: Any]] {
            for q in quotas {
                if let name = q["quotaName"] as? String ?? q["name"] as? String,
                   let used = q["used"] as? Double, let limit = q["limit"] as? Double, limit > 0 {
                    windows.append(QuotaWindow(id: name, label: name, usedPercentage: min(1.0, used / limit), resetAt: nil))
                }
            }
        }

        if windows.isEmpty {
            AppLogger.log("[GeminiProvider] No quota data, keys: \(Array(json.keys))")
            windows.append(QuotaWindow(id: "gemini", label: "Connected", usedPercentage: 0, resetAt: nil))
        }
        return windows
    }

    /// Reads OAuth client credentials from the Gemini CLI's installed source.
    /// These are public "installed application" credentials, not secrets.
    private func readGeminiClientCredentials() -> (clientId: String, clientSecret: String) {
        // Try to find the Gemini CLI's oauth2.js file
        let searchPaths = [
            // nvm installations
            ProcessInfo.processInfo.environment["HOME"].map { "\($0)/.nvm/versions/node" },
            // Homebrew
            "/usr/local/lib/node_modules/@google/gemini-cli",
            "/opt/homebrew/lib/node_modules/@google/gemini-cli",
            // Global npm
            "/usr/local/lib/node_modules/@google/gemini-cli"
        ].compactMap { $0 }

        for basePath in searchPaths {
            // Search for oauth2.js recursively
            if let clientId = extractFromGeminiSource(basePath: basePath) {
                return clientId
            }
        }

        // Environment variable fallback
        let envId = ProcessInfo.processInfo.environment["GEMINI_OAUTH_CLIENT_ID"] ?? ""
        let envSecret = ProcessInfo.processInfo.environment["GEMINI_OAUTH_CLIENT_SECRET"] ?? ""
        return (envId, envSecret)
    }

    private func extractFromGeminiSource(basePath: String) -> (String, String)? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: basePath) else { return nil }

        while let file = enumerator.nextObject() as? String {
            if file.hasSuffix("oauth2.js") && file.contains("gemini-cli") {
                let fullPath = "\(basePath)/\(file)"
                guard let content = try? String(contentsOfFile: fullPath, encoding: .utf8) else { continue }

                // Extract OAUTH_CLIENT_ID
                var clientId = ""
                var clientSecret = ""

                if let range = content.range(of: "OAUTH_CLIENT_ID = '") {
                    let start = range.upperBound
                    if let end = content[start...].firstIndex(of: "'") {
                        clientId = String(content[start..<end])
                    }
                }
                if let range = content.range(of: "OAUTH_CLIENT_SECRET = '") {
                    let start = range.upperBound
                    if let end = content[start...].firstIndex(of: "'") {
                        clientSecret = String(content[start..<end])
                    }
                }

                if !clientId.isEmpty && !clientSecret.isEmpty {
                    AppLogger.log("[GeminiProvider] Found client credentials in \(fullPath)")
                    return (clientId, clientSecret)
                }
            }
        }
        return nil
    }

    /// Reads email from ~/.gemini/google_accounts.json
    static func readLocalEmail() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let path = home.appendingPathComponent(".gemini/google_accounts.json")
        guard let data = try? Data(contentsOf: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["active"] as? String
    }
}
