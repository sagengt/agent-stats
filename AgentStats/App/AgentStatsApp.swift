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
        let keychain = KeychainManager.shared
        let credentialStore = CredentialStore(keychain: keychain)
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
        Task {
            AppLogger.log("[AgentStatsApp] Starting initial refresh (\(snapshot.activeAccounts.count) active account(s))")
            await orch.requestRefresh()
            await orch.startAutoRefresh(interval: 300) // 5 minutes
        }
    }

    // MARK: Preferences

    @AppStorage(MenuBarDisplayModeKey.userDefaultsKey)
    private var displayModeRaw: String = MenuBarDisplayMode.label.rawValue

    private var displayMode: MenuBarDisplayMode {
        MenuBarDisplayMode(rawValue: displayModeRaw) ?? .label
    }

    // MARK: Scene

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(viewModel)
                .environmentObject(authCoordinator)
                .environmentObject(languageManager)
        } label: {
            menuBarLabel
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

    // MARK: Menu bar label

    @ViewBuilder
    private var menuBarLabel: some View {
        switch displayMode {
        case .label:
            MenuBarLabelView(results: viewModel.results)

        case .carousel:
            StackedBarView(results: viewModel.results)

        case .compact:
            compactLabel
        }
    }

    /// Icon-only label tinted by the highest quota usage colour.
    private var compactLabel: some View {
        let pct = viewModel.highestQuotaPercentage ?? 0
        let tint: Color = {
            switch pct {
            case ..<0.5:  return .green
            case ..<0.8:  return .orange
            default:      return .red
            }
        }()
        return Image(systemName: "chart.bar.fill")
            .foregroundStyle(viewModel.results.isEmpty ? .primary : tint)
    }
}
