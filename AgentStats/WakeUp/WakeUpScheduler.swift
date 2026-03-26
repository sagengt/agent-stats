import Foundation

// MARK: - WakeUpScheduler

/// Manages a LaunchAgent plist that wakes AgentStats at user-specified hours.
///
/// The LaunchAgent is installed at `~/Library/LaunchAgents/<agentLabel>.plist`
/// and registered with `launchctl`. On each scheduled wake, it executes
/// the `open -a AgentStats` command, which brings the app to the foreground
/// and triggers a background refresh if the app is already running.
///
/// All operations are performed synchronously from the call site. Callers should
/// dispatch to a background context when invoking install/uninstall.
struct WakeUpScheduler: Sendable {

    // MARK: Constants

    static let agentLabel = "com.agentstats.wakeup"

    private static var plistURL: URL {
        let launchAgentsURL = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
        return launchAgentsURL.appendingPathComponent("\(agentLabel).plist")
    }

    // MARK: - Install

    /// Creates the LaunchAgent plist and loads it with `launchctl`.
    ///
    /// - Parameter hours: The UTC hours (0–23) at which the agent should fire.
    ///   Duplicate values are deduplicated; an empty set removes any existing agent.
    /// - Throws: `WakeUpSchedulerError` or any `FileManager`/`Process` error.
    static func install(hours: [Int]) throws {
        let unique = Array(Set(hours.filter { (0...23).contains($0) })).sorted()

        // If no valid hours, treat as uninstall.
        guard !unique.isEmpty else {
            try uninstall()
            return
        }

        // Ensure LaunchAgents directory exists.
        let launchAgentsDir = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
        try FileManager.default.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true)

        // Resolve the app bundle path for the open command.
        let appPath = Bundle.main.bundlePath

        // Build the plist dictionary.
        // StartCalendarInterval fires at each specified minute/hour combination.
        let calendarIntervals: [[String: Any]] = unique.map { hour in
            ["Hour": hour, "Minute": 0]
        }

        let plist: [String: Any] = [
            "Label": agentLabel,
            "ProgramArguments": ["/usr/bin/open", "-a", appPath],
            "StartCalendarInterval": calendarIntervals,
            "RunAtLoad": false,
            "StandardOutPath": "/dev/null",
            "StandardErrorPath": "/dev/null"
        ]

        // Serialise to plist.
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )

        // If the agent is already loaded, unload first to avoid conflicts.
        if isInstalled() {
            try runLaunchctl(["unload", plistURL.path])
        }

        // Write the plist file.
        try data.write(to: plistURL, options: .atomic)

        // Load the agent.
        try runLaunchctl(["load", plistURL.path])
    }

    // MARK: - Uninstall

    /// Unloads and removes the LaunchAgent plist.
    ///
    /// - Throws: `WakeUpSchedulerError` or any file system error.
    static func uninstall() throws {
        guard FileManager.default.fileExists(atPath: plistURL.path) else { return }

        // Unload from launchctl (ignore errors if the agent was not loaded).
        try? runLaunchctl(["unload", plistURL.path])

        // Remove the plist file.
        try FileManager.default.removeItem(at: plistURL)
    }

    // MARK: - State queries

    /// Returns `true` when the LaunchAgent plist file exists on disk.
    static func isInstalled() -> Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    /// Parses the installed plist and returns the list of scheduled hours.
    ///
    /// Returns an empty array when the agent is not installed or the plist
    /// cannot be parsed.
    static func installedHours() -> [Int] {
        guard
            isInstalled(),
            let data = try? Data(contentsOf: plistURL),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
            let dict = plist as? [String: Any]
        else {
            return []
        }

        // StartCalendarInterval can be a single dict or an array of dicts.
        if let intervals = dict["StartCalendarInterval"] as? [[String: Any]] {
            return intervals.compactMap { $0["Hour"] as? Int }.sorted()
        } else if let single = dict["StartCalendarInterval"] as? [String: Any],
                  let hour = single["Hour"] as? Int {
            return [hour]
        }
        return []
    }

    // MARK: - Private helpers

    /// Runs `launchctl` with the given arguments and throws if the exit code is non-zero.
    private static func runLaunchctl(_ args: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw WakeUpSchedulerError.launchctlFailed(
                args: args,
                exitCode: process.terminationStatus
            )
        }
    }
}

// MARK: - WakeUpSchedulerError

enum WakeUpSchedulerError: LocalizedError {

    case launchctlFailed(args: [String], exitCode: Int32)

    var errorDescription: String? {
        switch self {
        case .launchctlFailed(let args, let code):
            return "launchctl \(args.joined(separator: " ")) failed with exit code \(code)."
        }
    }
}
