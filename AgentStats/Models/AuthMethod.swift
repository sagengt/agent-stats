import Foundation

/// Describes how a service provider acquires its authentication credentials.
enum AuthMethod: Sendable {
    /// The user must log in via a web-based OAuth flow rendered in a `WKWebView`.
    /// `loginURL` is the starting URL for the authentication page.
    case oauthWebView(loginURL: URL)

    /// The user provides a personal access token (PAT) through the settings UI.
    case personalAccessToken

    /// The user provides a raw API key through the settings UI.
    case apiKey

    /// No authentication is required; the service is publicly accessible or
    /// credentials are handled transparently (e.g. via system keychain).
    case none

    /// Credentials are imported from a local CLI auth file (e.g. ~/.codex/auth.json).
    case importFromCLI
}
