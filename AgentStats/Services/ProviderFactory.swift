import Foundation

/// Creates concrete `UsageProviderProtocol` instances for a given `RegisteredAccount`.
struct ProviderFactory: Sendable {

    let credentialStore: CredentialStore
    let apiClient: APIClient

    func makeProvider(for account: RegisteredAccount) -> any UsageProviderProtocol {
        let key = account.key
        switch key.serviceType {
        case .claude:
            return ClaudeUsageProvider(account: key, credentialStore: credentialStore, apiClient: apiClient)
        case .codex:
            return CodexUsageProvider(account: key, credentialStore: credentialStore, apiClient: apiClient)
        case .gemini:
            return GeminiUsageProvider(account: key, credentialStore: credentialStore, apiClient: apiClient)
        case .zai:
            return ZaiUsageProvider(account: key, credentialStore: credentialStore, apiClient: apiClient)
        }
    }
}
