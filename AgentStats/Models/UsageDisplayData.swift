import Foundation

/// Unified display value produced by any usage provider. Each case maps to
/// the concrete model type that the corresponding service exposes.
enum UsageDisplayData: Sendable {
    /// Percentage-based rolling-window quota (Claude Code, Codex, Z.ai).
    case quota(QuotaWindow)

    /// Raw token consumption summary (Gemini, Copilot).
    case tokenSummary(TokenUsageSummary)

    /// Interactive editor session metrics (Cursor, OpenCode).
    case activity(SessionActivity)

    /// Data could not be obtained; `reason` describes why.
    case unavailable(reason: String)
}
