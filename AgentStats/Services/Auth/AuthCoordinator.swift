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

    /// Incremented every time an account is successfully activated.
    /// Observers (e.g. ProvidersSettingsTab) can react to this to reload.
    @Published var activationCount: Int = 0

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
        // Guard against duplicate captures (WebView can fire multiple times)
        guard isAuthenticating, authenticatingAccountKey == accountKey else {
            AppLogger.log("[AuthCoordinator] Ignoring duplicate/stale capture for \(accountKey.accountId.prefix(8))")
            return
        }

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

        // Try to resolve the user's email or name from the service API
        // and update the account label accordingly.
        await resolveAccountLabel(for: accountKey, material: material)

        isAuthenticating = false
        authenticatingAccountKey = nil
        activationCount += 1
        AppLogger.log("[AuthCoordinator] Account activated: \(accountKey)")
    }

    /// Called by `OAuthWebView.Coordinator` when the login flow encounters an error.
    func handleAuthError(_ error: String, for accountKey: AccountKey) async {
        closeAuthWindow()
        authError = error
        isAuthenticating = false
        await accountManager.discardProvisional(accountKey)
        authenticatingAccountKey = nil
    }

    // MARK: Account label resolution

    /// Attempts to fetch the user's email or name from the service API
    /// and updates the account label from the default "Claude Code" etc.
    private func resolveAccountLabel(for key: AccountKey, material: CredentialMaterial) async {
        let apiClient = APIClient.shared

        var headers: [String: String] = [:]
        let cookieHeader = material.httpCookies()
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")
        if !cookieHeader.isEmpty { headers["Cookie"] = cookieHeader }
        if let auth = material.authorizationHeader { headers["Authorization"] = auth }
        if let ua = material.userAgent { headers["User-Agent"] = ua }
        headers["Accept"] = "application/json"

        do {
            switch key.serviceType {
            case .claude:
                // Try multiple endpoints to get user info
                let endpoints = [
                    "https://claude.ai/api/auth/user",
                    "https://claude.ai/api/account"
                ]
                for endpoint in endpoints {
                    do {
                        let url = URL(string: endpoint)!
                        let data = try await apiClient.fetchRaw(from: url, headers: headers)
                        let preview = String(data: data.prefix(500), encoding: .utf8) ?? ""
                        AppLogger.log("[AuthCoordinator] \(endpoint) response: \(preview)")
                        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            let email = json["email_address"] as? String
                                ?? json["email"] as? String
                            let name = json["full_name"] as? String
                                ?? json["name"] as? String
                            if let label = email ?? name {
                                AppLogger.log("[AuthCoordinator] Resolved Claude label: \(label)")
                                await accountManager.updateLabel(for: key, label: label)
                                break
                            }
                        }
                    } catch {
                        AppLogger.log("[AuthCoordinator] \(endpoint) failed: \(error.localizedDescription)")
                        continue
                    }
                }

            case .codex:
                // Try reading email from ~/.codex/auth.json JWT first
                if let label = readCodexEmailFromAuthJson() {
                    AppLogger.log("[AuthCoordinator] Resolved Codex label from auth.json: \(label)")
                    await accountManager.updateLabel(for: key, label: label)
                } else {
                    // Fallback: try API
                    let url = URL(string: "https://chatgpt.com/backend-api/me")!
                    let data = try await apiClient.fetchRaw(from: url, headers: headers)
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        let email = json["email"] as? String
                        let name = json["name"] as? String
                        let label = email ?? name ?? key.serviceType.displayName
                        await accountManager.updateLabel(for: key, label: label)
                    }
                }

            default:
                break
            }
        } catch {
            AppLogger.log("[AuthCoordinator] Could not resolve account label: \(error.localizedDescription)")
            // Non-fatal — keep the default label.
        }
    }

    /// Reads user email from ~/.codex/auth.json by decoding the JWT id_token.
    private func readCodexEmailFromAuthJson() -> String? {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/auth.json").path
        guard let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = json["tokens"] as? [String: Any],
              let idToken = tokens["id_token"] as? String else {
            return nil
        }
        // Decode JWT payload (second segment)
        let parts = idToken.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var base64 = String(parts[1])
        // Pad base64
        while base64.count % 4 != 0 { base64 += "=" }
        guard let payloadData = Data(base64Encoded: base64),
              let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else {
            return nil
        }
        return payload["email"] as? String ?? payload["name"] as? String
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
