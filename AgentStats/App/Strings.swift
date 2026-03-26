import Foundation

// MARK: - L10n

/// Compile-time-safe localisation strings for AgentStats.
///
/// Usage:
/// ```swift
/// let label = L10n.string(.appName, language: .en)
/// // or via LanguageManager:
/// let label = languageManager[.refresh]
/// ```
enum L10n {

    // MARK: - StringKey

    enum StringKey: String, CaseIterable {
        // General
        case appName
        case refresh
        case settings
        case quit
        case cancel
        case save
        case done
        case enabled
        case disabled
        case test
        case language

        // Services
        case claude
        case codex
        case gemini
        case copilot
        case cursor
        case opencode
        case zai

        // Usage
        case usedPercent
        case remaining
        case resetIn
        case tokens
        case cost
        case requests
        case sessions
        case noData
        case unavailable

        // Settings tabs
        case general
        case services
        case history
        case pacemaker
        case wakeup
        case notifications

        // General settings
        case displayMode
        case autoRefresh
        case launchAtLogin
        case menuBarAppearance
        case systemIntegration
        case refreshInterval
        case minuteSingular
        case minutePlural

        // Notification settings
        case thresholdNotifications
        case enableNotifications
        case notificationPermissionRequired
        case notificationPermissionBody
        case warningThreshold
        case dangerThreshold
        case sendTestNotification
        case testNotificationDescription
        case grantAccess
        case openSystemSettings
        case notificationPermissionMissing

        // Notification content
        case warningTitle
        case dangerTitle
        case usageWarningBody
        case usageDangerBody
        case testNotificationTitle
        case testNotificationBody

        // Pacemaker
        case pacemakerDescription
        case onTrack
        case warningStatus
        case dangerStatus
    }

    // MARK: - Lookup

    /// Returns the localised string for `key` in the given `language`.
    ///
    /// Falls back to English when a key is missing from the target language table.
    static func string(_ key: StringKey, language: AppLanguage = .system) -> String {
        let resolved = language.resolved
        switch resolved {
        case .ja:
            return ja[key] ?? en[key] ?? key.rawValue
        default:
            return en[key] ?? key.rawValue
        }
    }

    // MARK: - English strings

    static let en: [StringKey: String] = [
        // General
        .appName:    "AgentStats",
        .refresh:    "Refresh",
        .settings:   "Settings",
        .quit:       "Quit AgentStats",
        .cancel:     "Cancel",
        .save:       "Save",
        .done:       "Done",
        .enabled:    "Enabled",
        .disabled:   "Disabled",
        .test:       "Test",
        .language:   "Language",

        // Services
        .claude:     "Claude Code",
        .codex:      "ChatGPT Codex",
        .gemini:     "Google Gemini",
        .copilot:    "GitHub Copilot",
        .cursor:     "Cursor",
        .opencode:   "OpenCode",
        .zai:        "Z.ai Coding Plan",

        // Usage
        .usedPercent: "%d%% used",
        .remaining:   "%d%% remaining",
        .resetIn:     "Resets in %@",
        .tokens:      "Tokens",
        .cost:        "Cost",
        .requests:    "Requests",
        .sessions:    "Sessions",
        .noData:      "No data",
        .unavailable: "Unavailable",

        // Settings tabs
        .general:       "General",
        .services:      "Services",
        .history:       "History",
        .pacemaker:     "Pacemaker",
        .wakeup:        "Wake Up",
        .notifications: "Notifications",

        // General settings
        .displayMode:       "Display Mode",
        .autoRefresh:       "Auto-Refresh",
        .launchAtLogin:     "Launch at Login",
        .menuBarAppearance: "Menu Bar Appearance",
        .systemIntegration: "System",
        .refreshInterval:   "Refresh Interval",
        .minuteSingular:    "minute",
        .minutePlural:      "minutes",

        // Notification settings
        .thresholdNotifications:     "Threshold Notifications",
        .enableNotifications:        "Enable Notifications",
        .notificationPermissionRequired: "Notification Permission Required",
        .notificationPermissionBody: "AgentStats needs notification permission to send threshold alerts. Please enable it in System Settings > Notifications.",
        .warningThreshold:           "Warning Threshold",
        .dangerThreshold:            "Danger Threshold",
        .sendTestNotification:       "Send Test Notification",
        .testNotificationDescription: "Verify that notifications appear correctly on your system.",
        .grantAccess:                "Grant Access",
        .openSystemSettings:         "Open System Settings",
        .notificationPermissionMissing: "Notification permission not granted.",

        // Notification content
        .warningTitle:        "%@ Usage Warning",
        .dangerTitle:         "%@ Usage Critical",
        .usageWarningBody:    "%@ window is %d%% used. Consider slowing down.",
        .usageDangerBody:     "%@ window is %d%% used. You may be rate-limited soon.",
        .testNotificationTitle: "AgentStats Notification Test",
        .testNotificationBody:  "Threshold notifications are working correctly.",

        // Pacemaker
        .pacemakerDescription: "Compares actual usage against expected even-pace consumption.",
        .onTrack:    "On Track",
        .warningStatus: "+%d%% ahead",
        .dangerStatus:  "+%d%% ahead (Critical)",
    ]

    // MARK: - Japanese strings

    static let ja: [StringKey: String] = [
        // General
        .appName:    "AgentStats",
        .refresh:    "更新",
        .settings:   "設定",
        .quit:       "AgentStats を終了",
        .cancel:     "キャンセル",
        .save:       "保存",
        .done:       "完了",
        .enabled:    "有効",
        .disabled:   "無効",
        .test:       "テスト",
        .language:   "言語",

        // Services
        .claude:     "Claude Code",
        .codex:      "ChatGPT Codex",
        .gemini:     "Google Gemini",
        .copilot:    "GitHub Copilot",
        .cursor:     "Cursor",
        .opencode:   "OpenCode",
        .zai:        "Z.ai コーディングプラン",

        // Usage
        .usedPercent: "%d%% 使用済み",
        .remaining:   "%d%% 残り",
        .resetIn:     "%@ 後にリセット",
        .tokens:      "トークン",
        .cost:        "コスト",
        .requests:    "リクエスト",
        .sessions:    "セッション",
        .noData:      "データなし",
        .unavailable: "取得不可",

        // Settings tabs
        .general:       "一般",
        .services:      "サービス",
        .history:       "履歴",
        .pacemaker:     "ペースメーカー",
        .wakeup:        "ウェイクアップ",
        .notifications: "通知",

        // General settings
        .displayMode:       "表示モード",
        .autoRefresh:       "自動更新",
        .launchAtLogin:     "ログイン時に起動",
        .menuBarAppearance: "メニューバーの表示",
        .systemIntegration: "システム",
        .refreshInterval:   "更新間隔",
        .minuteSingular:    "分",
        .minutePlural:      "分",

        // Notification settings
        .thresholdNotifications:     "しきい値通知",
        .enableNotifications:        "通知を有効にする",
        .notificationPermissionRequired: "通知の許可が必要です",
        .notificationPermissionBody: "しきい値アラートを送信するには通知の許可が必要です。システム設定 > 通知 から許可してください。",
        .warningThreshold:           "警告しきい値",
        .dangerThreshold:            "危険しきい値",
        .sendTestNotification:       "テスト通知を送信",
        .testNotificationDescription: "通知がシステムに正しく表示されるか確認します。",
        .grantAccess:                "アクセスを許可",
        .openSystemSettings:         "システム設定を開く",
        .notificationPermissionMissing: "通知の許可が付与されていません。",

        // Notification content
        .warningTitle:        "%@ 使用量警告",
        .dangerTitle:         "%@ 使用量が危険レベルです",
        .usageWarningBody:    "%@ ウィンドウが %d%% 使用されました。使用ペースを落とすことをお勧めします。",
        .usageDangerBody:     "%@ ウィンドウが %d%% 使用されました。まもなくレート制限される可能性があります。",
        .testNotificationTitle: "AgentStats 通知テスト",
        .testNotificationBody:  "しきい値通知が正常に動作しています。",

        // Pacemaker
        .pacemakerDescription: "実際の使用量と均等ペース消費量を比較します。",
        .onTrack:    "順調",
        .warningStatus: "+%d%% 先行",
        .dangerStatus:  "+%d%% 先行（危険）",
    ]
}
