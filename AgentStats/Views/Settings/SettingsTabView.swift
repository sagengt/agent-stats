import SwiftUI

// MARK: - SettingsTabView

/// Root settings window with General, Services, History, Pacemaker, WakeUp,
/// and Notifications tabs.
///
/// Replaces the Phase 2 two-tab implementation. Declared as the `Settings` scene
/// body in `AgentStatsApp`.
struct SettingsTabView: View {

    // MARK: Dependencies

    let historyStore: any UsageHistoryStoreProtocol

    // MARK: Environment

    @EnvironmentObject private var languageManager: LanguageManager

    // MARK: State

    @State private var selectedTab: SettingsTab = .general

    // MARK: Body

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsTab()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag(SettingsTab.general)

            ProvidersSettingsTab()
                .tabItem {
                    Label("Services", systemImage: "server.rack")
                }
                .tag(SettingsTab.providers)

            UsageHistoryTabView(historyStore: historyStore)
                .tabItem {
                    Label("History", systemImage: "clock")
                }
                .tag(SettingsTab.history)

            PacemakerSettingsView()
                .tabItem {
                    Label("Pacemaker", systemImage: "gauge.with.needle")
                }
                .tag(SettingsTab.pacemaker)

            WakeUpSettingsView()
                .tabItem {
                    Label("WakeUp", systemImage: "alarm")
                }
                .tag(SettingsTab.wakeup)

            ThresholdSettingsView()
                .tabItem {
                    Label("Notifications", systemImage: "bell.badge")
                }
                .tag(SettingsTab.notifications)
        }
        .frame(width: 600, height: 520)
    }
}

// MARK: - SettingsTab

private enum SettingsTab: String {
    case general
    case providers
    case history
    case pacemaker
    case wakeup
    case notifications
}

// MARK: - Preview

#if DEBUG
private final class PreviewHistoryStore: UsageHistoryStoreProtocol, @unchecked Sendable {
    func record(results: [ServiceUsageResult]) async {}
    func records(for service: ServiceType, accountKey: AccountKey?, since: Date, until: Date) async -> [UsageHistoryRecord] { [] }
    func availableServices() async -> [ServiceType] { [] }
}

#Preview("Settings") {
    SettingsTabView(historyStore: PreviewHistoryStore())
        .environmentObject(LanguageManager.shared)
}
#endif
