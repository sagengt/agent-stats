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

    // MARK: Init

    init() {
        // Build infrastructure actors.
        let keychain = KeychainManager.shared
        let credentialStore = CredentialStore(keychain: keychain)
        let resultStore = UsageResultStore()
        let historyStore = UsageHistoryStore()

        // Register concrete providers.
        let claudeProvider = ClaudeUsageProvider(credentialStore: credentialStore)
        let codexProvider = CodexUsageProvider(credentialStore: credentialStore)

        // Placeholder providers for services not yet implemented in Phase 1.
        // Replace each PlaceholderProvider with a concrete implementation as
        // the corresponding service is built out in subsequent phases.
        let geminiProvider  = PlaceholderProvider(serviceType: .gemini)
        let copilotProvider = PlaceholderProvider(serviceType: .copilot)
        let cursorProvider  = PlaceholderProvider(serviceType: .cursor)
        let opencodeProvider = PlaceholderProvider(serviceType: .opencode)
        let zaiProvider     = PlaceholderProvider(serviceType: .zai)

        let registry = ProviderRegistry(providers: [
            claudeProvider,
            codexProvider,
            geminiProvider,
            copilotProvider,
            cursorProvider,
            opencodeProvider,
            zaiProvider,
        ])

        // Wire orchestrator with the full provider graph.
        let orchestrator = RefreshOrchestrator(
            registry: registry,
            resultStore: resultStore,
            historyStore: historyStore as any UsageHistoryStoreProtocol
        )

        // Initialise StateObjects from the constructed graph.
        _viewModel = StateObject(wrappedValue: UsageViewModel(
            resultStore: resultStore,
            orchestrator: orchestrator
        ))
        _authCoordinator = StateObject(wrappedValue: AuthCoordinator(
            credentialStore: credentialStore
        ))
    }

    // MARK: Scene

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(viewModel)
                .environmentObject(authCoordinator)
        } label: {
            MenuBarLabelView(results: viewModel.results)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsPlaceholderView()
                .environmentObject(authCoordinator)
        }
    }
}

// MARK: - SettingsPlaceholderView

/// Phase 1 placeholder for the Settings window.
/// A full implementation will be provided in Phase 2.
private struct SettingsPlaceholderView: View {
    @EnvironmentObject var authCoordinator: AuthCoordinator

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("AgentStats Settings")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Full settings UI coming in Phase 2.")
                .foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(width: 400, height: 300)
    }
}
