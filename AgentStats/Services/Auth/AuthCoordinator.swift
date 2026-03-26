import SwiftUI
import WebKit

// MARK: - AuthCoordinatorDelegate

/// Notified when the OAuth WebView captures cookies from a successful login.
protocol AuthCoordinatorDelegate: AnyObject {
    func authCoordinator(
        _ coordinator: AuthCoordinator,
        didCaptureCookies cookies: [HTTPCookie],
        authorizationHeader: String?,
        userAgent: String?,
        for service: ServiceType
    )
}

// MARK: - AuthCoordinator

/// Coordinates authentication flows for all registered services.
///
/// `AuthCoordinator` owns the WebView window lifecycle and writes
/// completed credentials to `CredentialStore`. It runs on `@MainActor`
/// because it manages AppKit windows and `@Published` SwiftUI state.
@MainActor
final class AuthCoordinator: ObservableObject {

    // MARK: Published state

    /// `true` while an authentication window is open.
    @Published var isAuthenticating: Bool = false

    /// Human-readable error message from the most recent failed auth attempt.
    /// Cleared automatically when a new authentication begins.
    @Published var authError: String?

    /// The service currently being authenticated; `nil` when idle.
    @Published var authenticatingService: ServiceType?

    // MARK: Dependencies

    private let credentialStore: CredentialStore

    // MARK: Internal state

    /// The window hosting the `OAuthWebView` during an in-progress flow.
    private var authWindow: NSWindow?

    // MARK: Init

    init(credentialStore: CredentialStore) {
        self.credentialStore = credentialStore
    }

    // MARK: Public API

    /// Begins the authentication flow for `service` using `method`.
    ///
    /// For `.oauthWebView`, a floating `NSWindow` is opened containing an
    /// `OAuthWebView`. When the WebView signals that cookies have been
    /// captured the window is dismissed and credentials are persisted.
    ///
    /// Other auth methods (PAT, API key) are handled via the Settings UI
    /// and are not initiated from this method in Phase 1.
    func authenticate(service: ServiceType, method: AuthMethod) async {
        authError = nil
        authenticatingService = service
        isAuthenticating = true

        switch method {
        case .oauthWebView(let loginURL):
            openOAuthWindow(for: service, loginURL: loginURL)

        case .personalAccessToken, .apiKey:
            // Token/key entry is handled by the Settings view; nothing to do here.
            isAuthenticating = false
            authenticatingService = nil

        case .none:
            isAuthenticating = false
            authenticatingService = nil
        }
    }

    /// Removes stored credentials for `service` from `CredentialStore`.
    func signOut(service: ServiceType) async {
        await credentialStore.invalidate(for: service)
    }

    /// Called by `OAuthWebView.Coordinator` when the login page yields cookies.
    func handleCapturedCookies(
        _ cookies: [HTTPCookie],
        authorizationHeader: String?,
        userAgent: String?,
        for service: ServiceType
    ) async {
        closeAuthWindow()

        guard !cookies.isEmpty || authorizationHeader != nil else {
            authError = "No credentials were captured. Please try again."
            isAuthenticating = false
            authenticatingService = nil
            return
        }

        let cookieDTOs = cookies.map { CookieDTO(from: $0) }
        let material = CredentialMaterial(
            cookies: cookieDTOs.isEmpty ? nil : cookieDTOs,
            authorizationHeader: authorizationHeader,
            userAgent: userAgent,
            capturedAt: Date(),
            expiresAt: nil // Services without explicit expiry; rely on `needsReauth` check
        )

        await credentialStore.save(for: service, material: material)

        isAuthenticating = false
        authenticatingService = nil
    }

    /// Called by `OAuthWebView.Coordinator` when the login flow encounters an error.
    func handleAuthError(_ error: String, for service: ServiceType) {
        closeAuthWindow()
        authError = error
        isAuthenticating = false
        authenticatingService = nil
    }

    // MARK: Private helpers

    private func openOAuthWindow(for service: ServiceType, loginURL: URL) {
        closeAuthWindow() // Dismiss any existing window first.

        let webView = OAuthWebView(
            url: loginURL,
            service: service,
            coordinator: self
        )
        let hosting = NSHostingView(rootView: webView)
        hosting.frame = NSRect(x: 0, y: 0, width: 960, height: 720)

        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Sign in to \(service.displayName)"
        window.contentView = hosting
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.delegate = WindowCloseDelegate(onClose: { [weak self] in
            guard let self else { return }
            if self.isAuthenticating {
                self.authError = "Authentication was cancelled."
                self.isAuthenticating = false
                self.authenticatingService = nil
            }
        })

        authWindow = window
    }

    private func closeAuthWindow() {
        authWindow?.close()
        authWindow = nil
    }
}

// MARK: - WindowCloseDelegate

/// Thin `NSWindowDelegate` that fires a closure when the window is closed.
private final class WindowCloseDelegate: NSObject, NSWindowDelegate, @unchecked Sendable {
    private let onClose: @MainActor () -> Void

    init(onClose: @escaping @MainActor () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            self.onClose()
        }
    }
}
