import Foundation

/// Errors that service providers may throw during fetch operations.
enum ProviderError: Error, LocalizedError, Sendable {
    /// The provider has no stored credential or the credential has expired.
    case notAuthenticated

    /// A network or API-level fetch attempt failed.
    case fetchFailed(String)

    /// The server response could not be decoded into the expected model.
    case parseError(String)

    // MARK: LocalizedError

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "No valid credentials found. Please sign in to continue."
        case .fetchFailed(let detail):
            return "Fetch failed: \(detail)"
        case .parseError(let detail):
            return "Could not parse server response: \(detail)"
        }
    }
}
