import SwiftUI
import WebKit

// MARK: - AuthCoordinator

/// Coordinates authentication flows for all registered services.
///
/// `AuthCoordinator` owns the WebView window lifecycle, manages the
/// provisional account lifecycle via `AccountManager`, and writes
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

    /// The account key currently being authenticated; `nil` when idle.
    @Published var authenticatingAccountKey: AccountKey?

    // MARK: Dependencies

    private let credentialStore: CredentialStore
    private let accountManager: AccountManager

    // MARK: Internal state

    /// The window hosting the `OAuthWebView` during an in-progress flow.
    private var authWindow: NSWindow?

    /// Strong reference to the window's delegate to prevent premature deallocation.
    /// `NSWindow.delegate` is a `weak` property, so we must retain the delegate independently.
    private var authWindowDelegate: WindowCloseDelegate?

    // MARK: Init

    init(credentialStore: CredentialStore, accountManager: AccountManager) {
        self.credentialStore = credentialStore
        self.accountManager = accountManager
    }

    // MARK: Public API

    /// Begins the authentication flow for `service` using `method`.
    ///
    /// A provisional account is registered with `AccountManager` before the
    /// OAuth window opens so that the account is tracked from the start of
    /// the flow. On success the account is activated; on failure or cancel
    /// it is discarded.
    ///
    /// For `.oauthWebView`, a floating `NSWindow` is opened containing an
    /// `OAuthWebView`. When the WebView signals that cookies have been
    /// captured the window is dismissed and credentials are persisted.
    ///
    /// Other auth methods (PAT, API key) are handled via the Settings UI
    /// and are not initiated from this method.
    func authenticate(service: ServiceType, method: AuthMethod) async {
        authError = nil
        isAuthenticating = true

        switch method {
        case .oauthWebView(let loginURL):
            // Register a provisional account before starting the OAuth flow.
            let accountKey = await accountManager.registerProvisional(
                service: service,
                label: service.displayName
            )
            authenticatingAccountKey = accountKey
            openOAuthWindow(for: accountKey, loginURL: loginURL)

        case .personalAccessToken, .apiKey:
            // Token/key entry is handled by the Settings view; nothing to do here.
            isAuthenticating = false
            authenticatingAccountKey = nil

        case .none:
            isAuthenticating = false
            authenticatingAccountKey = nil
        }
    }

    /// Removes stored credentials for `accountKey` and unregisters the account.
    func signOut(accountKey: AccountKey) async {
        await accountManager.unregister(accountKey)
    }

    /// Called by `OAuthWebView.Coordinator` when the login page yields cookies.
    func handleCapturedCookies(
        _ cookies: [HTTPCookie],
        authorizationHeader: String?,
        userAgent: String?,
        for accountKey: AccountKey
    ) async {
        closeAuthWindow()

        guard !cookies.isEmpty || authorizationHeader != nil else {
            authError = "No credentials were captured. Please try again."
            isAuthenticating = false
            await accountManager.discardProvisional(accountKey)
            authenticatingAccountKey = nil
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

        await credentialStore.save(for: accountKey, material: material)
        await accountManager.activateAccount(accountKey)

        isAuthenticating = false
        authenticatingAccountKey = nil
    }

    /// Called by `OAuthWebView.Coordinator` when the login flow encounters an error.
    func handleAuthError(_ error: String, for accountKey: AccountKey) async {
        closeAuthWindow()
        authError = error
        isAuthenticating = false
        await accountManager.discardProvisional(accountKey)
        authenticatingAccountKey = nil
    }

    // MARK: Private helpers

    private func openOAuthWindow(for accountKey: AccountKey, loginURL: URL) {
        closeAuthWindow() // Dismiss any existing window first.

        let webView = OAuthWebView(
            url: loginURL,
            accountKey: accountKey,
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
        window.title = "Sign in to \(accountKey.serviceType.displayName)"
        window.contentView = hosting
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        let closeDelegate = WindowCloseDelegate(onClose: { [weak self] in
            guard let self else { return }
            if self.isAuthenticating {
                self.authError = "Authentication was cancelled."
                self.isAuthenticating = false
                Task {
                    await self.accountManager.discardProvisional(accountKey)
                }
                self.authenticatingAccountKey = nil
            }
        })
        window.delegate = closeDelegate
        authWindowDelegate = closeDelegate

        authWindow = window
    }

    private func closeAuthWindow() {
        authWindow?.close()
        authWindow = nil
        authWindowDelegate = nil
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
