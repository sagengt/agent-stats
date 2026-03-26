import SwiftUI
import WebKit

// MARK: - OAuthWebView

/// An `NSViewRepresentable` that wraps `WKWebView` for the OAuth login flow.
///
/// After a successful login the `Coordinator` extracts all cookies from the
/// `WKHTTPCookieStore` and any `Authorization` header observed in network
/// responses, then forwards them to `AuthCoordinator`.
struct OAuthWebView: NSViewRepresentable {

    // MARK: Input

    /// The starting URL for the authentication page (e.g. `https://claude.ai`).
    let url: URL

    /// The account key being authenticated — carries both service type and account ID.
    let accountKey: AccountKey

    /// Back-reference to the coordinator that manages credential persistence.
    weak var coordinator: AuthCoordinator?

    // MARK: Derived

    /// Service type derived from `accountKey`.
    private var service: ServiceType { accountKey.serviceType }

    // MARK: NSViewRepresentable

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // Use the default persistent data store so that OAuth redirects,
        // CAPTCHA challenges, and multi-step logins can retain state across
        // navigations. Credentials are extracted once login completes and
        // stored via CredentialStore; the WebView's cookie jar is not relied
        // upon for long-term persistence.
        configuration.websiteDataStore = .default()

        // Install the script message handler so the page JS can signal readiness
        // if needed (currently unused but reserved for future handshake).
        configuration.userContentController.add(
            context.coordinator,
            name: "agentStatsAuth"
        )

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        // No dynamic updates needed; the URL is fixed at construction time.
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(accountKey: accountKey, authCoordinator: coordinator)
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {

        // MARK: State

        private let accountKey: AccountKey
        private var service: ServiceType { accountKey.serviceType }
        private weak var authCoordinator: AuthCoordinator?

        /// Set of URL host patterns that indicate a successful login.
        /// When navigation reaches one of these hosts cookie extraction begins.
        private let successHostPatterns: Set<String>

        /// Captured `Authorization` header value observed in network traffic.
        private var capturedAuthorizationHeader: String?

        /// Guards against triggering credential capture more than once.
        private var hasCapture = false

        // MARK: Init

        init(accountKey: AccountKey, authCoordinator: AuthCoordinator?) {
            self.accountKey = accountKey
            self.authCoordinator = authCoordinator
            self.successHostPatterns = Self.successPatterns(for: accountKey.serviceType)
        }

        // MARK: WKNavigationDelegate

        nonisolated func webView(
            _ webView: WKWebView,
            didFinish navigation: WKNavigation!
        ) {
            Task { @MainActor in
                guard let url = webView.url else { return }
                self.evaluateLoginSuccess(for: url, in: webView)
            }
        }

        nonisolated func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            Task { @MainActor in
                // Ignore cancellations that occur during normal redirects.
                let nsError = error as NSError
                guard nsError.domain != NSURLErrorDomain ||
                      nsError.code != NSURLErrorCancelled else { return }

                await self.authCoordinator?.handleAuthError(
                    "Page load failed: \(error.localizedDescription)",
                    for: self.accountKey
                )
            }
        }

        nonisolated func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationResponse: WKNavigationResponse,
            decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
        ) {
            // Inspect response headers for Authorization tokens emitted by some APIs.
            if let httpResponse = navigationResponse.response as? HTTPURLResponse {
                let auth = httpResponse.value(forHTTPHeaderField: "Authorization")
                    ?? httpResponse.value(forHTTPHeaderField: "X-Auth-Token")
                if let auth, !auth.isEmpty {
                    Task { @MainActor in
                        self.capturedAuthorizationHeader = auth
                    }
                }
            }
            decisionHandler(.allow)
        }

        // MARK: WKScriptMessageHandler

        nonisolated func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            // Reserved for future JS-bridge handshake; no-op in Phase 1.
        }

        // MARK: Private helpers

        private func evaluateLoginSuccess(for url: URL, in webView: WKWebView) {
            guard !hasCapture else { return }

            let host = url.host ?? ""
            let path = url.path

            AppLogger.log("[OAuthWebView] Navigation finished: host=\(host) path=\(path)")

            let isSuccess = successHostPatterns.contains(where: { host.hasSuffix($0) })
            guard isSuccess else {
                AppLogger.log("[OAuthWebView] Host \(host) not in success patterns: \(successHostPatterns)")
                return
            }

            let isPostLogin = isPostLoginURL(url)
            guard isPostLogin else {
                AppLogger.log("[OAuthWebView] Path \(path) is not a post-login URL — waiting for redirect")
                return
            }

            AppLogger.log("[OAuthWebView] Login success detected! Capturing credentials...")
            hasCapture = true
            extractCredentials(from: webView)
        }

        private func extractCredentials(from webView: WKWebView) {
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    AppLogger.log("[OAuthWebView] Total cookies captured: \(cookies.count)")
                    let userAgent = try? await webView.evaluateJavaScript("navigator.userAgent") as? String

                    // Filter cookies to only those belonging to the service's
                    // known domains.  This prevents credentials from unrelated
                    // sites (visited during SSO redirects) from being persisted.
                    let allowedDomains = self.service.allowedCookieDomains
                    let filteredCookies: [HTTPCookie]
                    if allowedDomains.isEmpty {
                        // No domain whitelist defined — pass all cookies through
                        // (should not happen for OAuth-WebView services, but safe
                        // fallback for future additions).
                        filteredCookies = cookies
                    } else {
                        filteredCookies = cookies.filter { cookie in
                            allowedDomains.contains(where: { cookie.domain.contains($0) })
                        }
                    }

                    AppLogger.log("[OAuthWebView] Filtered cookies: \(filteredCookies.count) (domains: \(allowedDomains))")
                    if filteredCookies.isEmpty {
                        AppLogger.log("[OAuthWebView] WARNING: No cookies matched allowed domains!")
                        for cookie in cookies.prefix(10) {
                            AppLogger.log("[OAuthWebView]   cookie: \(cookie.domain) / \(cookie.name)")
                        }
                    }

                    await self.authCoordinator?.handleCapturedCookies(
                        filteredCookies,
                        authorizationHeader: self.capturedAuthorizationHeader,
                        userAgent: userAgent,
                        for: self.accountKey
                    )
                }
            }
        }

        /// Returns `true` when `url` is a post-authentication destination.
        private func isPostLoginURL(_ url: URL) -> Bool {
            let path = url.path
            switch service {
            case .claude:
                // Exclude login/signup pages — only trigger on the actual app pages.
                let loginPaths = ["/login", "/signup", "/oauth", "/verify", "/consent"]
                if loginPaths.contains(where: { path.hasPrefix($0) }) { return false }
                // Claude lands on the main app after successful OAuth.
                return path == "/" || path.hasPrefix("/new") || path.hasPrefix("/chat")
                    || path.hasPrefix("/project") || path.hasPrefix("/settings")
            case .codex:
                let loginPaths = ["/auth", "/login", "/signup"]
                if loginPaths.contains(where: { path.hasPrefix($0) }) { return false }
                return path == "/" || path.hasPrefix("/c/") || path.hasPrefix("/g/")
                    || path.hasPrefix("/codex") || path.hasPrefix("/gpts")
            default:
                return true
            }
        }

        private static func successPatterns(for service: ServiceType) -> Set<String> {
            switch service {
            case .claude:   return ["claude.ai"]
            case .codex:    return ["chatgpt.com"]
            case .gemini:   return ["gemini.google.com", "accounts.google.com"]
            case .copilot:  return ["github.com"]
            case .cursor:   return ["cursor.sh", "cursor.com"]
            case .opencode: return ["opencode.ai"]
            case .zai:      return ["z.ai"]
            }
        }
    }
}
