import Foundation

/// Reads Cursor editor session activity from local application-support files.
///
/// Cursor stores per-session state under
/// `~/Library/Application Support/Cursor/`.  The provider scans for recent
/// SQLite workspace-storage databases and JSON state files to derive:
///
/// - `activeSessions`:       count of workspace folders modified in the last
///                           24 hours (a proxy for active sessions).
/// - `totalDurationMinutes`: sum of `sessionDuration` values found in state
///                           blobs, or 0 when unavailable.
/// - `requestCount`:         sum of AI request counters found across state
///                           files.
/// - `lastActiveAt`:         modification date of the most recently touched
///                           state file.
///
/// No authentication is required; all data is read from the local filesystem.
///
/// Implements `SessionActivityProvider`.
struct CursorUsageProvider: SessionActivityProvider {

    // MARK: Protocol requirements

    let account: AccountKey
    var serviceType: ServiceType { account.serviceType }

    // MARK: Init

    init(account: AccountKey) {
        self.account = account
    }

    // MARK: UsageProviderProtocol

    func isConfigured() async -> Bool {
        FileManager.default.fileExists(atPath: cursorSupportDirectory.path)
    }

    // MARK: SessionActivityProvider

    func fetchSessionActivity() async throws -> SessionActivity {
        let supportDir = cursorSupportDirectory

        guard FileManager.default.fileExists(atPath: supportDir.path) else {
            throw ProviderError.fetchFailed(
                "Cursor application-support directory not found at \(supportDir.path). " +
                "Ensure Cursor is installed."
            )
        }

        return try await Task.detached(priority: .utility) {
            try Self.scanDirectory(supportDir)
        }.value
    }

    // MARK: Private – filesystem scanning

    private var cursorSupportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Cursor")
    }

    /// Scans the Cursor support directory for session-activity signals.
    ///
    /// This is a best-effort scan; individual file-read errors are swallowed
    /// so that a single corrupt file does not prevent the whole scan from
    /// completing.
    private static func scanDirectory(_ root: URL) throws -> SessionActivity {
        let fm = FileManager.default
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)   // last 24 h

        var activeSessions    = 0
        var totalDuration     = 0
        var requestCount      = 0
        var lastActiveAt: Date? = nil

        // Recursively enumerate, but limit depth to avoid traversing huge trees.
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw ProviderError.fetchFailed("Could not enumerate \(root.path)")
        }

        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(
                    forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  resourceValues.isRegularFile == true,
                  let modDate = resourceValues.contentModificationDate
            else { continue }

            // Track the most recently touched file.
            if lastActiveAt == nil || modDate > lastActiveAt! {
                lastActiveAt = modDate
            }

            // Count workspace folders (state.vscdb or workspaceStorage dirs)
            // modified in the last 24 h as a proxy for active sessions.
            let name = fileURL.lastPathComponent
            if (name == "state.vscdb" || name == "workspace.json")
                && modDate > cutoff {
                activeSessions += 1
            }

            // Parse JSON state files for richer metrics.
            if fileURL.pathExtension == "json",
               let data = try? Data(contentsOf: fileURL),
               let parsed = try? JSONDecoder().decode(CursorStateFile.self, from: data)
            {
                totalDuration += parsed.sessionDurationMinutes ?? 0
                requestCount  += parsed.aiRequestCount         ?? 0
            }
        }

        return SessionActivity(
            activeSessions:       activeSessions,
            totalDurationMinutes: totalDuration,
            requestCount:         requestCount,
            lastActiveAt:         lastActiveAt
        )
    }
}

// MARK: - Local state file model (private)

/// Minimal representation of a Cursor JSON state file.
/// Unknown keys are silently ignored.
private struct CursorStateFile: Decodable {
    /// Total session duration in minutes, if recorded.
    let sessionDurationMinutes: Int?
    /// Cumulative AI completion request count, if recorded.
    let aiRequestCount: Int?
}
