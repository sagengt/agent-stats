import Foundation

/// Lightweight capability and metadata registry for all supported service types.
///
/// `ServiceCatalog` replaces `ProviderRegistry` as the source of truth for
/// per-service static metadata (auth method, display info, etc.).  Unlike
/// `ProviderRegistry` it holds no live provider instances — those are managed
/// by `AccountProviderStore`.
struct ServiceCatalog: Sendable {

    // MARK: - Auth method

    /// Returns the authentication mechanism required by `service`.
    static func authMethod(for service: ServiceType) -> AuthMethod {
        switch service {
        case .claude:
            return .oauthWebView(loginURL: URL(string: "https://claude.ai")!)
        case .codex:
            return .importFromCLI
        case .gemini:
            return .apiKey
        case .copilot:
            return .personalAccessToken
        case .cursor, .opencode:
            return .none
        case .zai:
            return .apiKey
        }
    }
}
