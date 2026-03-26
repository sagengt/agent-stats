import Foundation

/// Adopted by any usage provider that requires user-supplied authentication
/// credentials before it can make API calls. The `authMethod` property
/// communicates to the onboarding UI which flow should be presented.
protocol CredentialRequired {
    /// The mechanism used to obtain and refresh credentials for this service.
    var authMethod: AuthMethod { get }
}
