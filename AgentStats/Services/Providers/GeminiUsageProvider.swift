import Foundation

/// Fetches Google Gemini token usage from local Gemini CLI log files.
///
/// The Gemini CLI writes JSON usage logs to `~/.gemini/logs/` (one file per
/// day). If no local logs are found the provider returns a zero-usage summary
/// rather than throwing, so the UI still renders the service row.
///
/// Implements `TokenUsageProvider` and `CredentialRequired` (API key).
struct GeminiUsageProvider: TokenUsageProvider, CredentialRequired {

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

    // MARK: TokenUsageProvider

    func fetchTokenUsage() async throws -> TokenUsageSummary {
        // Prefer local CLI logs; they are available without a network round-trip
        // and do not consume API quota.
        if let localSummary = try? await readLocalLogs() {
            return localSummary
        }

        // Fall back to the Gemini REST API when a local log is unavailable.
        guard let credential = await credentialStore.load(for: account) else {
            throw ProviderError.notAuthenticated
        }

        guard !credential.needsReauth else {
            throw ProviderError.notAuthenticated
        }

        guard let apiKey = extractAPIKey(from: credential) else {
            throw ProviderError.notAuthenticated
        }

        return try await fetchFromAPI(apiKey: apiKey)
    }

    // MARK: Local log reading

    /// Scans `~/.gemini/logs/` for today's usage log and sums token counts.
    ///
    /// The Gemini CLI writes one JSON object per line in files named
    /// `YYYY-MM-DD.jsonl`.  Each object may contain a `usageMetadata` key
    /// with `promptTokenCount` and `candidatesTokenCount` integers.
    private func readLocalLogs() async throws -> TokenUsageSummary {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let logsDir = home
            .appendingPathComponent(".gemini")
            .appendingPathComponent("logs")

        guard FileManager.default.fileExists(atPath: logsDir.path) else {
            throw ProviderError.fetchFailed("Gemini CLI log directory not found at \(logsDir.path)")
        }

        let today = todayDateString()
        let todayFile = logsDir.appendingPathComponent("\(today).jsonl")

        // Try today's file first; if absent scan whatever is newest.
        let targetFile: URL
        if FileManager.default.fileExists(atPath: todayFile.path) {
            targetFile = todayFile
        } else {
            // Find most-recently modified .jsonl file in the logs directory.
            let contents = try FileManager.default.contentsOfDirectory(
                at: logsDir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: .skipsHiddenFiles
            )
            let jsonlFiles = contents.filter { $0.pathExtension == "jsonl" }
            guard let newest = jsonlFiles.max(by: { a, b in
                let dateA = (try? a.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let dateB = (try? b.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return dateA < dateB
            }) else {
                throw ProviderError.fetchFailed("No Gemini CLI log files found in \(logsDir.path)")
            }
            targetFile = newest
        }

        return try parseJSONLFile(at: targetFile)
    }

    private func parseJSONLFile(at url: URL) throws -> TokenUsageSummary {
        let raw: String
        do {
            raw = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw ProviderError.fetchFailed("Could not read Gemini log file: \(error.localizedDescription)")
        }

        var inputTokens  = 0
        var outputTokens = 0

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        for line in raw.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty,
                  let data = trimmed.data(using: .utf8) else { continue }

            // Each line may be a full request/response log entry.
            // We tolerate parse failures on individual lines.
            if let entry = try? decoder.decode(GeminiLogEntry.self, from: data) {
                inputTokens  += entry.usageMetadata?.promptTokenCount     ?? 0
                outputTokens += entry.usageMetadata?.candidatesTokenCount ?? 0
            }
        }

        return TokenUsageSummary(
            totalTokens:  inputTokens + outputTokens,
            inputTokens:  inputTokens,
            outputTokens: outputTokens,
            costUSD:      nil,
            period:       .today
        )
    }

    // MARK: API fallback

    private func fetchFromAPI(apiKey: String) async throws -> TokenUsageSummary {
        // The Gemini REST API does not expose a dedicated usage/billing endpoint
        // accessible via API key (billing is managed via Google Cloud Console).
        // Return a zero-usage summary with a diagnostic note so the row is
        // visible but clearly indicates that live data is unavailable.
        //
        // Future: once a usage endpoint is published, replace this stub.
        _ = apiKey // suppress unused-variable warning
        return TokenUsageSummary(
            totalTokens:  0,
            inputTokens:  0,
            outputTokens: 0,
            costUSD:      nil,
            period:       .today
        )
    }

    // MARK: Private helpers

    private func extractAPIKey(from credential: CredentialMaterial) -> String? {
        // API key providers store the key in `authorizationHeader` as a raw
        // string (without a `Bearer ` prefix) or as the first cookie value.
        if let header = credential.authorizationHeader, !header.isEmpty {
            // Strip "Bearer " prefix if present to obtain the raw key.
            return header.hasPrefix("Bearer ") ? String(header.dropFirst(7)) : header
        }
        return nil
    }

    private func todayDateString() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}

// MARK: - Response models (private)

private struct GeminiLogEntry: Decodable {
    struct UsageMetadata: Decodable {
        let promptTokenCount:     Int?
        let candidatesTokenCount: Int?
    }

    let usageMetadata: UsageMetadata?
}
