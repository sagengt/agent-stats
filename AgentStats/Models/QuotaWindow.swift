import Foundation

/// A single rolling-window quota entry for services that express limits as
/// percentage consumption (Claude Code, ChatGPT Codex, Z.ai Coding Plan).
struct QuotaWindow: Sendable, Codable, Identifiable {
    /// Window identifier, e.g. `"5h"`, `"weekly"`.
    let id: String

    /// Human-readable label, e.g. `"5 Hour"`, `"Weekly"`.
    let label: String

    /// Fraction of the quota consumed, in the range `0.0 – 1.0`.
    let usedPercentage: Double

    /// Timestamp at which the window resets; `nil` when unknown.
    let resetAt: Date?

    /// Fraction of the quota still available. Derived from `usedPercentage`.
    var remainingPercentage: Double { 1.0 - usedPercentage }
}
