import Foundation
import Combine

// MARK: - AppLanguage

/// Supported UI languages for AgentStats.
enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    /// Follow the OS locale setting.
    case system
    /// English.
    case en
    /// Japanese.
    case ja

    var id: String { rawValue }

    /// Human-readable name shown in the language picker.
    var displayName: String {
        switch self {
        case .system: return "System Default"
        case .en:     return "English"
        case .ja:     return "日本語"
        }
    }

    /// The BCP-47 language tag for this language (nil for `.system`).
    var languageCode: String? {
        switch self {
        case .system: return nil
        case .en:     return "en"
        case .ja:     return "ja"
        }
    }

    /// The effective language to use for localisation, resolving `.system`
    /// against the device's preferred languages.
    var resolved: AppLanguage {
        guard case .system = self else { return self }
        // Check the device's first preferred language.
        let preferred = Locale.preferredLanguages.first ?? "en"
        if preferred.hasPrefix("ja") { return .ja }
        return .en
    }
}

// MARK: - LanguageManager

/// Observable object that drives language selection throughout the app.
///
/// The chosen language is persisted in `UserDefaults` under the key
/// `agentstats.language`.  Views observe `currentLanguage` to rebuild
/// localised strings reactively when the user switches languages.
final class LanguageManager: ObservableObject {

    // MARK: Shared instance

    static let shared = LanguageManager()

    // MARK: Published state

    /// The currently selected language. Changing this value triggers a UI rebuild.
    @Published var currentLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(currentLanguage.rawValue, forKey: Self.defaultsKey)
        }
    }

    // MARK: Constants

    private static let defaultsKey = "agentstats.language"

    // MARK: Init

    init() {
        let raw = UserDefaults.standard.string(forKey: Self.defaultsKey) ?? ""
        self.currentLanguage = AppLanguage(rawValue: raw) ?? .system
    }

    // MARK: Public API

    /// Returns the localised string for `key` in the currently selected language.
    func string(_ key: L10n.StringKey) -> String {
        L10n.string(key, language: currentLanguage.resolved)
    }

    /// Shorthand subscript so callers can write `manager[.appName]`.
    subscript(key: L10n.StringKey) -> String {
        string(key)
    }
}
