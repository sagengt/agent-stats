import SwiftUI

// MARK: - AgentStatsApp

/// Application entry point.
///
/// Constructs the full dependency graph at launch, wires it into the SwiftUI
/// environment, and declares the `MenuBarExtra` scene that drives the menu bar
/// icon and popover.
@main
struct AgentStatsApp: App {

    // MARK: View models

    @StateObject private var viewModel: UsageViewModel
    @StateObject private var authCoordinator: AuthCoordinator
    @StateObject private var languageManager: LanguageManager = .shared

    /// Retained so the Settings window can present the full history tab.
    private let historyStore: UsageHistoryStore

    /// Actor that fires quota threshold notifications after each refresh cycle.
    private let notificationManager: ThresholdNotificationManager = ThresholdNotificationManager()

    // MARK: Init

    init() {
        // Build infrastructure actors.
        let credentialStore = CredentialStore.shared
        let resultStore = UsageResultStore()
        let historyStore = UsageHistoryStore()

        // Load the persisted account snapshot (strips orphan provisionals on cold launch).
        let snapshot = AccountSnapshotLoader.loadSync()

        // Build the provider factory and bootstrap the provider store from persisted accounts.
        let apiClient = APIClient.shared
        let factory = ProviderFactory(credentialStore: credentialStore, apiClient: apiClient)
        let providerStore = AccountProviderStore(
            accounts: snapshot.activeAccounts,
            factory: factory
        )

        // Wire orchestrator with the account-keyed provider graph.
        let orchestrator = RefreshOrchestrator(
            providerStore: providerStore,
            resultStore: resultStore,
            historyStore: historyStore as any UsageHistoryStoreProtocol
        )

        // Build the account manager that owns registration / deletion lifecycle.
        let accountManager = AccountManager(
            snapshot: snapshot,
            providerStore: providerStore,
            credentialStore: credentialStore,
            resultStore: resultStore,
            orchestrator: orchestrator
        )

        // Retain history store so the Settings window can access it.
        self.historyStore = historyStore

        // Initialise StateObjects from the constructed graph.
        _viewModel = StateObject(wrappedValue: UsageViewModel(
            resultStore: resultStore,
            orchestrator: orchestrator,
            accountManager: accountManager
        ))
        _authCoordinator = StateObject(wrappedValue: AuthCoordinator(
            credentialStore: credentialStore,
            accountManager: accountManager
        ))

        // Request notification authorization on first launch (non-blocking).
        Task {
            await ThresholdNotificationManager.requestAuthorization()
        }

        // Kick off initial refresh + auto-refresh on launch.
        let orch = orchestrator
        let mgr = accountManager
        Task {
            AppLogger.log("[AgentStatsApp] Starting initial refresh (\(snapshot.activeAccounts.count) active account(s))")
            // Resolve any missing account labels at startup
            await Self.resolveDefaultLabels(accounts: snapshot.activeAccounts, manager: mgr)
            await orch.requestRefresh()
            await orch.startAutoRefresh(interval: 300) // 5 minutes
        }
    }

    // MARK: Scene

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(viewModel)
                .environmentObject(authCoordinator)
                .environmentObject(languageManager)
        } label: {
            MenuBarLabelView(results: viewModel.results)
        }
        .menuBarExtraStyle(.window)
        .onChange(of: viewModel.lastRefreshedAt) { _, _ in
            // Evaluate thresholds after every result update.
            Task { await notificationManager.evaluate(results: viewModel.results) }
        }
        // IMPORTANT: Kick off the initial refresh + auto-refresh on app launch.
        // Without this, results remain empty until the user manually clicks Refresh.

        Settings {
            SettingsTabView(historyStore: historyStore)
                .environmentObject(authCoordinator)
                .environmentObject(viewModel)
                .environmentObject(languageManager)
                .onAppear {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
        }
    }

    // MARK: - Label resolution

    private static func resolveDefaultLabels(accounts: [RegisteredAccount], manager: AccountManager) async {
        for account in accounts {
            let service = account.key.serviceType
            let label = account.label.trimmingCharacters(in: .whitespacesAndNewlines)
            if !label.isEmpty && label != service.displayName { continue }

            var resolved: String?
            switch service {
            case .codex:
                resolved = decodeCodexEmail()
            case .gemini:
                resolved = GeminiUsageProvider.readLocalEmail()
            default:
                break
            }

            if let label = resolved {
                await manager.updateLabel(for: account.key, label: label)
                AppLogger.log("[AgentStatsApp] Resolved label for \(service): \(label)")
            }
        }
    }

    private static func decodeCodexEmail() -> String? {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/auth.json").path
        guard let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = json["tokens"] as? [String: Any],
              let idToken = tokens["id_token"] as? String else { return nil }
        let parts = idToken.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let payloadData = Data(base64Encoded: base64),
              let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else { return nil }
        return payload["email"] as? String ?? payload["name"] as? String
    }
}
