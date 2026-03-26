import Foundation

/// Reads OpenCode session activity from local log and state files.
///
/// OpenCode (the open-source AI coding agent) writes session logs to
/// `~/.opencode/` (or `~/.config/opencode/`).  The provider scans both
/// locations for JSONL conversation logs and derives:
///
/// - `activeSessions`:       number of session log files modified in the
///                           last 24 hours.
/// - `totalDurationMinutes`: estimated from session timestamps where
///                           available, otherwise 0.
/// - `requestCount`:         number of user-message entries found across all
///                           recent session logs.
/// - `lastActiveAt`:         modification date of the most recently touched
///                           log file.
///
/// No authentication is required; all data is read from the local filesystem.
///
/// Implements `SessionActivityProvider`.
struct OpenCodeUsageProvider: SessionActivityProvider {

    // MARK: Protocol requirements

    let account: AccountKey
    var serviceType: ServiceType { account.serviceType }

    // MARK: Init

    init(account: AccountKey) {
        self.account = account
    }

    // MARK: UsageProviderProtocol

    func isConfigured() async -> Bool {
        openCodeDirectories.contains { FileManager.default.fileExists(atPath: $0.path) }
    }

    // MARK: SessionActivityProvider

    func fetchSessionActivity() async throws -> SessionActivity {
        // Locate the first existing OpenCode data directory.
        guard let dataDir = openCodeDirectories.first(where: {
            FileManager.default.fileExists(atPath: $0.path)
        }) else {
            throw ProviderError.fetchFailed(
                "OpenCode data directory not found. Checked: " +
                openCodeDirectories.map(\.path).joined(separator: ", ")
            )
        }

        return try await Task.detached(priority: .utility) {
            try Self.scanDirectory(dataDir)
        }.value
    }

    // MARK: Private – candidate directories

    private var openCodeDirectories: [URL] {
        let home   = FileManager.default.homeDirectoryForCurrentUser
        let config = FileManager.default.urls(
            for: .libraryDirectory, in: .userDomainMask
        ).first ?? home

        return [
            home.appendingPathComponent(".opencode"),
            home.appendingPathComponent(".config").appendingPathComponent("opencode"),
            config.appendingPathComponent("Application Support").appendingPathComponent("opencode"),
        ]
    }

    // MARK: Private – scanning

    /// Scans `root` for OpenCode session log files and derives activity metrics.
    private static func scanDirectory(_ root: URL) throws -> SessionActivity {
        let fm     = FileManager.default
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)

        var activeSessions    = 0
        var requestCount      = 0
        var lastActiveAt: Date? = nil
        var earliestSession:  Date? = nil
        var latestSession:    Date? = nil

        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw ProviderError.fetchFailed("Could not enumerate \(root.path)")
        }

        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(
                    forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  resourceValues.isRegularFile == true,
                  let modDate = resourceValues.contentModificationDate
            else { continue }

            // Track overall last-active.
            if lastActiveAt == nil || modDate > lastActiveAt! {
                lastActiveAt = modDate
            }

            let ext  = fileURL.pathExtension
            let name = fileURL.lastPathComponent

            // OpenCode stores conversation logs as .jsonl or session-*.json files.
            guard ext == "jsonl" || (ext == "json" && name.hasPrefix("session")) else { continue }

            if modDate > cutoff {
                activeSessions += 1
            }

            // Count user messages as a proxy for AI request count.
            if let data = try? Data(contentsOf: fileURL) {
                let (msgs, start, end) = parseSessionLog(data: data, fileExtension: ext)
                requestCount += msgs

                if let s = start {
                    if earliestSession == nil || s < earliestSession! { earliestSession = s }
                }
                if let e = end {
                    if latestSession == nil || e > latestSession! { latestSession = e }
                }
            }
        }

        // Estimate total duration from session timestamp range.
        let durationMinutes: Int
        if let start = earliestSession, let end = latestSession, end > start {
            durationMinutes = Int(end.timeIntervalSince(start) / 60)
        } else {
            durationMinutes = 0
        }

        return SessionActivity(
            activeSessions:       activeSessions,
            totalDurationMinutes: durationMinutes,
            requestCount:         requestCount,
            lastActiveAt:         lastActiveAt
        )
    }

    /// Parses a session log file and returns `(userMessageCount, firstTimestamp, lastTimestamp)`.
    private static func parseSessionLog(
        data: Data,
        fileExtension: String
    ) -> (Int, Date?, Date?) {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy  = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601

        var messageCount = 0
        var firstDate: Date? = nil
        var lastDate:  Date? = nil

        let raw = String(data: data, encoding: .utf8) ?? ""

        if fileExtension == "jsonl" {
            // Each line is a separate JSON object.
            for line in raw.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty,
                      let lineData = trimmed.data(using: .utf8),
                      let entry = try? decoder.decode(OpenCodeLogEntry.self, from: lineData)
                else { continue }

                if entry.role == "user" || entry.type == "user" {
                    messageCount += 1
                }
                if let ts = entry.timestamp ?? entry.createdAt {
                    if firstDate == nil || ts < firstDate! { firstDate = ts }
                    if lastDate  == nil || ts > lastDate!  { lastDate  = ts }
                }
            }
        } else {
            // Attempt to parse the whole file as a session JSON object.
            if let session = try? decoder.decode(OpenCodeSessionFile.self, from: data) {
                messageCount = session.messages?.filter {
                    $0.role == "user" || $0.type == "user"
                }.count ?? 0
                firstDate = session.createdAt
                lastDate  = session.updatedAt
            }
        }

        return (messageCount, firstDate, lastDate)
    }
}

// MARK: - Local log models (private)

private struct OpenCodeLogEntry: Decodable {
    let role:      String?
    let type:      String?
    let timestamp: Date?
    let createdAt: Date?
}

private struct OpenCodeSessionFile: Decodable {
    struct Message: Decodable {
        let role: String?
        let type: String?
    }

    let messages:  [Message]?
    let createdAt: Date?
    let updatedAt: Date?
}
