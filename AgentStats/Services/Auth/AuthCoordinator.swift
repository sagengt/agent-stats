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
    @Published var activationCount: Int = 0

    /// API key input state
    @Published var showingAPIKeyInput: Bool = false
    @Published var apiKeyInputService: ServiceType?

    /// PAT input state
    @Published var showingPATInput: Bool = false
    @Published var patInputService: ServiceType?

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

        case .apiKey:
            // For services with local auth files (Gemini), try auto-detect first
            if service == .gemini {
                await autoDetectGemini(service: service)
            } else {
                // Show API key input for Z.ai etc.
                showingAPIKeyInput = true
                apiKeyInputService = service
            }
            isAuthenticating = false
            authenticatingAccountKey = nil

        case .personalAccessToken:
            showingPATInput = true
            patInputService = service
            isAuthenticating = false
            authenticatingAccountKey = nil

        case .none:
            // For services like Cursor/OpenCode - auto-detect local files
            let accountKey = await accountManager.registerProvisional(service: service, label: service.displayName)
            await accountManager.activateAccount(accountKey)
            isAuthenticating = false
            authenticatingAccountKey = nil
            activationCount += 1

        case .importFromCLI:
            await importFromCodexCLI(service: service)
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

    // MARK: Gemini auto-detect

    /// Auto-detects Gemini CLI credentials from ~/.gemini/
    private func autoDetectGemini(service: ServiceType) async {
        let accountKey = await accountManager.registerProvisional(service: service, label: service.displayName)

        // Check if Gemini CLI is installed and has credentials
        let home = FileManager.default.homeDirectoryForCurrentUser
        let oauthPath = home.appendingPathComponent(".gemini/oauth_creds.json")

        if FileManager.default.fileExists(atPath: oauthPath.path) {
            // Gemini CLI OAuth detected — no need for manual API key
            let label = GeminiUsageProvider.readLocalEmail() ?? service.displayName
            await accountManager.activateAccount(accountKey)
            await accountManager.updateLabel(for: accountKey, label: label)
            activationCount += 1
            AppLogger.log("[AuthCoordinator] Gemini auto-detected: \(label)")
        } else {
            // No local Gemini CLI — show API key input
            await accountManager.discardProvisional(accountKey)
            showingAPIKeyInput = true
            apiKeyInputService = service
        }
    }

    /// Imports Codex credentials from ~/.codex/auth.json.
    private func importFromCodexCLI(service: ServiceType) async {
        guard let codexCred = CodexCredential.fromAuthJson() else {
            authError = "Could not read ~/.codex/auth.json. Make sure the Codex CLI is installed and you are signed in."
            AppLogger.log("[AuthCoordinator] Codex auth.json not found or invalid")
            return
        }

        // Check for duplicate account (same chatgptUserId already registered)
        let existing = await accountManager.allAccounts()
        if existing.contains(where: {
            $0.key.serviceType == service &&
            $0.key.accountId == codexCred.chatgptUserId
        }) {
            authError = "This Codex user (\(codexCred.email ?? codexCred.chatgptUserId)) is already registered."
            AppLogger.log("[AuthCoordinator] Codex user already registered: \(codexCred.chatgptUserId)")
            return
        }

        let label = codexCred.email ?? service.displayName
        // Use chatgptUserId (user-level, unique per person) not chatgptAccountId (org-level, shared)
        let accountKey = AccountKey(serviceType: service, accountId: codexCred.chatgptUserId)

        // Register using the stable chatgptUserId as accountId
        await accountManager.registerWithKey(accountKey, label: label)

        let encoded = try? JSONEncoder().encode(codexCred)
        let material = CredentialMaterial(
            cookies: nil,
            authorizationHeader: nil,
            userAgent: nil,
            capturedAt: Date(),
            expiresAt: codexCred.expiresAt,
            providerMetadata: encoded
        )

        await credentialStore.save(for: accountKey, material: material)
        await accountManager.activateAccount(accountKey)
        activationCount += 1
        AppLogger.log("[AuthCoordinator] Codex account imported: \(label)")
    }

    /// Called when user submits an API key from the input view.
    func submitAPIKey(_ key: String, for service: ServiceType) async {
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let accountKey = await accountManager.registerProvisional(service: service, label: service.displayName)

        let material = CredentialMaterial(
            cookies: nil,
            authorizationHeader: "Bearer \(trimmedKey)",
            userAgent: nil,
            capturedAt: Date(),
            expiresAt: nil
        )

        await credentialStore.save(for: accountKey, material: material)
        await accountManager.activateAccount(accountKey)
        activationCount += 1
        showingAPIKeyInput = false
        apiKeyInputService = nil
        AppLogger.log("[AuthCoordinator] API key saved for \(service)")
    }

    /// Called when user submits a PAT from the input view.
    func submitPAT(_ token: String, for service: ServiceType) async {
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let accountKey = await accountManager.registerProvisional(service: service, label: service.displayName)

        let material = CredentialMaterial(
            cookies: nil,
            authorizationHeader: "token \(trimmedToken)",
            userAgent: nil,
            capturedAt: Date(),
            expiresAt: nil
        )

        await credentialStore.save(for: accountKey, material: material)
        await accountManager.activateAccount(accountKey)
        activationCount += 1
        showingPATInput = false
        patInputService = nil
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
                // Resolve label from stored CodexCredential metadata
                if let cred = await credentialStore.load(for: key),
                   let metaData = cred.providerMetadata,
                   let codexCred = try? JSONDecoder().decode(CodexCredential.self, from: metaData),
                   let email = codexCred.email {
                    AppLogger.log("[AuthCoordinator] Resolved Codex label from stored credential: \(email)")
                    await accountManager.updateLabel(for: key, label: email)
                }

            default:
                break
            }
        } catch {
            AppLogger.log("[AuthCoordinator] Could not resolve account label: \(error.localizedDescription)")
            // Non-fatal — keep the default label.
        }
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
