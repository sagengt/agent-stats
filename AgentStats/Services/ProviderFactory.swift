import Foundation

/// Creates concrete `UsageProviderProtocol` instances for a given `RegisteredAccount`.
///
/// The factory is stateless and `Sendable`; it holds only shared infrastructure
/// that is safe to access across concurrency boundaries.
struct ProviderFactory: Sendable {

    // MARK: - Dependencies

    let credentialStore: CredentialStore
    let apiClient: APIClient

    // MARK: - Factory method

    /// Returns the appropriate concrete provider for `account.key.serviceType`.
    ///
    /// Falls back to `PlaceholderProvider` for service types that do not yet
    /// have a production implementation.
    func makeProvider(for account: RegisteredAccount) -> any UsageProviderProtocol {
        let key = account.key
        switch key.serviceType {
        case .claude:
            return ClaudeUsageProvider(
                account: key,
                credentialStore: credentialStore,
                apiClient: apiClient
            )
        case .codex:
            return CodexUsageProvider(
                account: key,
                credentialStore: credentialStore,
                apiClient: apiClient
            )
        case .gemini:
            return GeminiUsageProvider(
                account: key,
                credentialStore: credentialStore,
                apiClient: apiClient
            )
        case .copilot:
            return CopilotUsageProvider(
                account: key,
                credentialStore: credentialStore,
                apiClient: apiClient
            )
        case .cursor:
            return CursorUsageProvider(account: key)
        case .opencode:
            return OpenCodeUsageProvider(account: key)
        case .zai:
            return ZaiUsageProvider(
                account: key,
                credentialStore: credentialStore,
                apiClient: apiClient
            )
        }
    }
}
