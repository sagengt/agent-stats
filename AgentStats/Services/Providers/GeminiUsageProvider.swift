import Foundation

/// Fetches Google Gemini usage from local CLI log files.
///
/// Uses the AgentBar approach: scans `~/.gemini/tmp/*/logs.json` to count
/// user prompts for the current day. No API calls or credentials needed.
///
/// See docs/gemini-integration-spec.md for details.
struct GeminiUsageProvider: QuotaWindowProvider, CredentialRequired {

    let account: AccountKey
    var serviceType: ServiceType { account.serviceType }
    let authMethod: AuthMethod = .apiKey  // Gemini auto-detects local files

    private let credentialStore: CredentialStore
    private let apiClient: APIClient
    private let dailyRequestLimit: Double = 1000  // Free tier estimate

    init(account: AccountKey, credentialStore: CredentialStore, apiClient: APIClient = .shared) {
        self.account = account
        self.credentialStore = credentialStore
        self.apiClient = apiClient
    }

    func isConfigured() async -> Bool {
        // Configured if Gemini CLI logs exist
        let home = FileManager.default.homeDirectoryForCurrentUser
        let tmpDir = home.appendingPathComponent(".gemini/tmp")
        return FileManager.default.fileExists(atPath: tmpDir.path)
    }

    func fetchQuotaWindows() async throws -> [QuotaWindow] {
        AppLogger.log("[GeminiProvider] fetchQuotaWindows START")

        let todayCount = countTodayPrompts()
        AppLogger.log("[GeminiProvider] Today's prompts: \(todayCount)")

        let pct = min(1.0, Double(todayCount) / dailyRequestLimit)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1,
            to: Calendar.current.startOfDay(for: Date()))

        return [
            QuotaWindow(
                id: "daily",
                label: "Today (\(todayCount) prompts)",
                usedPercentage: pct,
                resetAt: tomorrow
            )
        ]
    }

    // MARK: - Local log scanning

    private func countTodayPrompts() -> Int {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let tmpDir = home.appendingPathComponent(".gemini/tmp")
        let fm = FileManager.default

        guard let projectDirs = try? fm.contentsOfDirectory(atPath: tmpDir.path) else {
            return 0
        }

        // Use Pacific time for day boundary (matching AgentBar)
        let pacific = TimeZone(identifier: "America/Los_Angeles") ?? .current
        var cal = Calendar.current
        cal.timeZone = pacific
        let todayStart = cal.startOfDay(for: Date())

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let isoFallback = ISO8601DateFormatter()
        isoFallback.formatOptions = [.withInternetDateTime]

        var count = 0

        for dir in projectDirs {
            let logsPath = tmpDir.appendingPathComponent("\(dir)/logs.json")
            guard let data = try? Data(contentsOf: logsPath) else { continue }

            // Quick check: skip files not modified today
            if let attrs = try? fm.attributesOfItem(atPath: logsPath.path),
               let modDate = attrs[.modificationDate] as? Date,
               modDate < todayStart.addingTimeInterval(-86400) {
                continue  // Older than yesterday, skip
            }

            guard let records = try? JSONDecoder().decode([GeminiLogRecord].self, from: data) else {
                continue
            }

            for record in records {
                guard record.type == "user",
                      let message = record.message, !message.isEmpty,
                      isCountablePrompt(message),
                      let timestamp = record.timestamp else { continue }

                let date = isoFormatter.date(from: timestamp) ?? isoFallback.date(from: timestamp)
                guard let date, date >= todayStart else { continue }

                count += 1
            }
        }

        return count
    }

    private func isCountablePrompt(_ message: String) -> Bool {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return false }
        if trimmed.hasPrefix("/") { return false }
        if trimmed.lowercased() == "exit" || trimmed.lowercased() == "quit" { return false }
        return true
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

// MARK: - Log Record

private struct GeminiLogRecord: Decodable {
    let sessionId: String?
    let messageId: Int?
    let type: String?
    let message: String?
    let timestamp: String?
}
