import Foundation

// MARK: - PacemakerSettings

/// User-configurable thresholds for the Pacemaker feature.
///
/// Pacemaker compares actual quota consumption against the theoretically
/// expected consumption given a perfectly even pace throughout the reset window.
/// When the actual usage exceeds the expected pace by more than `warningDelta`
/// or `dangerDelta`, the UI surfaces a warning or danger indicator respectively.
struct PacemakerSettings: Codable, Sendable {

    // MARK: Properties

    /// Whether the Pacemaker feature is active.
    var enabled: Bool = false

    /// Fractional overage that triggers a warning (e.g. `0.10` = 10 pp ahead of expected pace).
    var warningDelta: Double = 0.10

    /// Fractional overage that triggers a danger alert (e.g. `0.20` = 20 pp ahead of expected pace).
    var dangerDelta: Double = 0.20

    // MARK: UserDefaults key

    private static let defaultsKey = "agentstats.pacemakerSettings"

    // MARK: Persistence

    /// Loads settings from `UserDefaults.standard`, returning defaults when absent.
    static func load() -> PacemakerSettings {
        guard
            let data = UserDefaults.standard.data(forKey: defaultsKey),
            let decoded = try? JSONDecoder().decode(PacemakerSettings.self, from: data)
        else {
            return PacemakerSettings()
        }
        return decoded
    }

    /// Persists the current settings to `UserDefaults.standard`.
    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: PacemakerSettings.defaultsKey)
    }
}

// MARK: - PacemakerStatus

/// The pacing health of a single `QuotaWindow` relative to expected even-pace usage.
enum PacemakerStatus: Sendable {

    /// Actual usage is at or below the expected pace, or the window has no reset timestamp.
    case onTrack

    /// Actual usage exceeds expected by more than `warningDelta` but less than `dangerDelta`.
    case warning(delta: Double)

    /// Actual usage exceeds expected by `dangerDelta` or more.
    case danger(delta: Double)

    // MARK: Evaluation

    /// Derives the pacemaker status for `window` given `settings`.
    ///
    /// - Parameters:
    ///   - window: The quota window to evaluate. Must have a non-nil `resetAt`.
    ///   - settings: The thresholds to apply.
    /// - Returns: `.onTrack` when the window has no reset timestamp, or when the
    ///   actual pace is at or below the expected even pace; `.warning` or `.danger`
    ///   otherwise.
    static func evaluate(window: QuotaWindow, settings: PacemakerSettings) -> PacemakerStatus {
        guard let resetAt = window.resetAt else {
            // Cannot evaluate pace without a known reset timestamp.
            return .onTrack
        }

        let now = Date()

        // Total window duration in seconds, measured backwards from resetAt.
        // We need to infer the window start from the current timestamp and resetAt.
        // Strategy: treat the window duration as the time between the previous reset
        // and the upcoming one. Because the exact window start is not stored in
        // QuotaWindow, we approximate it using the window `id` when parseable,
        // and fall back to inferring from resetAt - current progress.
        //
        // Safe fallback: if resetAt is in the past, the window is over → on track.
        guard resetAt > now else { return .onTrack }

        let secondsRemaining = resetAt.timeIntervalSince(now)

        // Estimate total window duration from the id string (e.g. "5h", "weekly").
        let totalDuration = windowDuration(id: window.id)
        guard let total = totalDuration, total > 0 else { return .onTrack }

        // Fraction of the window that has elapsed.
        let elapsed = max(0, total - secondsRemaining)
        let elapsedFraction = elapsed / total

        // At an even pace, `usedPercentage` should equal `elapsedFraction` at this moment.
        let expectedUsage = elapsedFraction
        let actualUsage = window.usedPercentage

        let delta = actualUsage - expectedUsage

        if delta >= settings.dangerDelta {
            return .danger(delta: delta)
        } else if delta >= settings.warningDelta {
            return .warning(delta: delta)
        } else {
            return .onTrack
        }
    }

    // MARK: Helpers

    /// Parses the window `id` string into a total duration in seconds.
    ///
    /// Recognised formats:
    /// - `"Xh"` — X hours (e.g. `"5h"`)
    /// - `"Xd"` — X days (e.g. `"7d"`)
    /// - `"weekly"` — 7 days
    /// - `"monthly"` — 30 days
    /// - `"Xm"` — X minutes (for testing)
    private static func windowDuration(id: String) -> TimeInterval? {
        let lower = id.lowercased()

        if lower == "weekly" { return 7 * 24 * 3600 }
        if lower == "monthly" { return 30 * 24 * 3600 }

        // Parse numeric prefix with unit suffix.
        let digits = lower.prefix(while: { $0.isNumber })
        guard let value = Double(digits) else { return nil }

        if lower.hasSuffix("h") { return value * 3600 }
        if lower.hasSuffix("d") { return value * 24 * 3600 }
        if lower.hasSuffix("m") { return value * 60 }

        return nil
    }
}

// MARK: - PacemakerStatus display helpers

extension PacemakerStatus {

    /// A short human-readable description of the status.
    var label: String {
        switch self {
        case .onTrack:           return "On Track"
        case .warning(let d):   return String(format: "+%.0f%% ahead", d * 100)
        case .danger(let d):    return String(format: "+%.0f%% ahead", d * 100)
        }
    }

    /// The delta value, or zero for `.onTrack`.
    var delta: Double {
        switch self {
        case .onTrack:          return 0
        case .warning(let d):  return d
        case .danger(let d):   return d
        }
    }
}
