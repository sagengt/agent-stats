import Foundation

// MARK: - Base protocol

/// Base requirement for all service-specific usage data providers. Conformers
/// must be `Sendable` to allow safe use across Swift concurrency task boundaries.
protocol UsageProviderProtocol: Sendable {
    /// The service this provider fetches data for.
    var serviceType: ServiceType { get }

    /// Returns `true` when the provider has sufficient credentials and
    /// configuration to perform a fetch without immediately failing.
    func isConfigured() async -> Bool
}

// MARK: - Specialised fetch protocols

/// A provider that exposes rolling-window percentage-based quota information.
/// Implemented by: Claude Code, ChatGPT Codex, Z.ai Coding Plan.
protocol QuotaWindowProvider: UsageProviderProtocol {
    /// Fetches all available quota windows for the service.
    /// Throws when the network request fails or the response cannot be parsed.
    func fetchQuotaWindows() async throws -> [QuotaWindow]
}

/// A provider that exposes raw token consumption and optional cost data.
/// Implemented by: Google Gemini, GitHub Copilot.
protocol TokenUsageProvider: UsageProviderProtocol {
    /// Fetches a token usage summary for the default reporting period.
    /// Throws when the network request fails or the response cannot be parsed.
    func fetchTokenUsage() async throws -> TokenUsageSummary
}

/// A provider that exposes interactive coding-session activity metrics.
/// Implemented by: Cursor, OpenCode.
protocol SessionActivityProvider: UsageProviderProtocol {
    /// Fetches the latest session activity snapshot.
    /// Throws when the network request fails or the response cannot be parsed.
    func fetchSessionActivity() async throws -> SessionActivity
}
