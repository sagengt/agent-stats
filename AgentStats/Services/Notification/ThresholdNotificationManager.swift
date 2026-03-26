import Foundation
import UserNotifications

// MARK: - ThresholdNotificationManager

/// Actor that monitors quota usage results and fires macOS notifications
/// when usage crosses configurable warning or danger thresholds.
///
/// A 10-second per-account cooldown prevents notification spam when the
/// data refresh interval is short.
actor ThresholdNotificationManager {

    // MARK: - ThresholdConfig

    struct ThresholdConfig: Codable, Sendable {
        /// Whether threshold notifications are enabled globally.
        var enabled: Bool = true

        /// Fraction of quota that triggers a warning notification (default 70%).
        var warningThreshold: Double = 0.7

        /// Fraction of quota that triggers a danger notification (default 90%).
        var dangerThreshold: Double = 0.9
    }

    // MARK: - Constants

    private static let defaultsKey = "agentstats.thresholdNotificationConfig"
    private static let cooldownInterval: TimeInterval = 10

    // MARK: - State

    private var config: ThresholdConfig
    private var lastNotified: [AccountKey: Date] = [:]

    // MARK: - Init

    init() {
        self.config = ThresholdNotificationManager.loadConfig()
    }

    // MARK: - Public API

    /// Evaluates all results and fires notifications for any account whose
    /// quota has crossed the warning or danger threshold.
    func evaluate(results: [ServiceUsageResult]) async {
        guard config.enabled else { return }
        for result in results {
            for data in result.displayData {
                if case .quota(let window) = data {
                    checkThreshold(window: window, account: result.accountKey)
                }
            }
        }
    }

    /// Replaces the current configuration and persists it to `UserDefaults`.
    func updateConfig(_ newConfig: ThresholdConfig) {
        config = newConfig
        ThresholdNotificationManager.saveConfig(newConfig)
    }

    /// Returns a copy of the current configuration.
    func currentConfig() -> ThresholdConfig {
        config
    }

    /// Sends a test notification to verify that the permission and delivery
    /// pipeline is working correctly.
    func sendTestNotification() async {
        let content = UNMutableNotificationContent()
        content.title = "AgentStats Notification Test"
        content.body = "Threshold notifications are working correctly."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "agentstats.test.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Authorization

    /// Requests macOS notification permission from the user.
    ///
    /// Returns `true` when permission is granted (or was already granted),
    /// `false` when the user denied or an error occurred.
    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .sound, .badge]
            )
        } catch {
            return false
        }
    }

    // MARK: - Private — threshold evaluation

    private func checkThreshold(window: QuotaWindow, account: AccountKey) {
        let usage = window.usedPercentage

        // Determine which (if any) level is breached — prefer the higher level.
        let level: NotificationLevel?
        if usage >= config.dangerThreshold {
            level = .danger
        } else if usage >= config.warningThreshold {
            level = .warning
        } else {
            level = nil
        }

        guard let level else { return }

        // Cooldown check — skip if we notified this account too recently.
        if let last = lastNotified[account] {
            guard Date().timeIntervalSince(last) >= Self.cooldownInterval else { return }
        }

        lastNotified[account] = Date()
        sendNotification(for: account, window: window, level: level)
    }

    private func sendNotification(
        for account: AccountKey,
        window: QuotaWindow,
        level: NotificationLevel
    ) {
        let content = UNMutableNotificationContent()
        let serviceName = account.serviceType.displayName
        let windowLabel = window.label
        let pct = Int(window.usedPercentage * 100)

        switch level {
        case .warning:
            content.title = "\(serviceName) Usage Warning"
            content.body = "\(windowLabel) window is \(pct)% used. Consider slowing down."
        case .danger:
            content.title = "\(serviceName) Usage Critical"
            content.body = "\(windowLabel) window is \(pct)% used. You may be rate-limited soon."
        }
        content.sound = .default

        // Identifier encodes account + window + level so that newer
        // notifications replace stale ones for the same slot.
        let identifier = "agentstats.threshold.\(account.serviceType.rawValue).\(account.accountId).\(window.id).\(level.rawValue)"

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil   // deliver immediately
        )

        UNUserNotificationCenter.current().add(request) { _ in
            // Fire-and-forget; delivery errors are non-fatal.
        }
    }

    // MARK: - Private — persistence

    private static func loadConfig() -> ThresholdConfig {
        guard
            let data = UserDefaults.standard.data(forKey: defaultsKey),
            let decoded = try? JSONDecoder().decode(ThresholdConfig.self, from: data)
        else {
            return ThresholdConfig()
        }
        return decoded
    }

    private static func saveConfig(_ config: ThresholdConfig) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}

// MARK: - NotificationLevel

private enum NotificationLevel: String {
    case warning
    case danger
}
