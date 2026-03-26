import Foundation

/// Editor session activity snapshot for services that track interactive
/// coding sessions rather than raw token or quota metrics (e.g. Cursor,
/// OpenCode).
struct SessionActivity: Sendable, Codable {
    /// Number of currently active editor sessions.
    let activeSessions: Int

    /// Aggregate wall-clock duration of all tracked sessions in minutes.
    let totalDurationMinutes: Int

    /// Total number of AI requests made across all sessions.
    let requestCount: Int

    /// Timestamp of the most recent activity event; `nil` when unavailable.
    let lastActiveAt: Date?
}
