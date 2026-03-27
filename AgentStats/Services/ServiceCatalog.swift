import Foundation

/// Lightweight capability and metadata registry for supported services.
struct ServiceCatalog: Sendable {

    static func authMethod(for service: ServiceType) -> AuthMethod {
        switch service {
        case .claude: return .oauthWebView(loginURL: URL(string: "https://claude.ai/login")!)
        case .codex:  return .importFromCLI
        case .gemini: return .apiKey
        case .zai:    return .apiKey
        }
    }
}
