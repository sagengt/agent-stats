import Foundation

// MARK: - ShellError

enum ShellError: Error, LocalizedError {
    case executionFailed(exitCode: Int32, stderr: String)
    case timeout
    case commandNotFound(String)

    var errorDescription: String? {
        switch self {
        case .executionFailed(let code, let stderr):
            let detail = stderr.isEmpty ? "(no stderr)" : stderr
            return "Shell command exited with code \(code): \(detail)"
        case .timeout:
            return "Shell command timed out."
        case .commandNotFound(let command):
            return "Command not found: \(command)"
        }
    }
}

// MARK: - ShellExecutor

/// Executes shell commands in a login shell so that PATH and other
/// shell-initialised environment variables (e.g. from `.zshrc`, `.bashrc`)
/// are available to tools like `ccusage`.
///
/// - Important: **App Sandbox compatibility.**
///   With `com.apple.security.app-sandbox` enabled, `Process` (and therefore
///   this executor) requires the
///   `com.apple.security.temporary-exception.files.absolute-path.read-write`
///   entitlement, or must be replaced with an XPC service that runs outside
///   the sandbox.  In Phase 1 the sandbox is enabled but `ShellExecutor` is
///   not called from the active code paths, so no additional entitlements are
///   needed yet.  When CLI-based providers (e.g. `ccusage`) are introduced in
///   a later phase, either add the required process entitlement or move shell
///   execution into a dedicated XPC helper bundle.
enum ShellExecutor {

    /// Runs `command` with `arguments` via the user's login shell.
    ///
    /// - Parameters:
    ///   - command:   The executable to invoke (resolved via PATH inside the shell).
    ///   - arguments: Additional arguments forwarded to the command.
    ///   - timeout:   Maximum wall-clock time to wait (default 60 s).
    /// - Returns: The trimmed standard output of the process.
    /// - Throws: `ShellError` on non-zero exit, timeout, or missing command.
    static func execute(
        command: String,
        arguments: [String] = [],
        timeout: TimeInterval = 60
    ) async throws -> String {
        // Build the full command string so the login shell can resolve PATH.
        // Arguments are individually shell-quoted to prevent word splitting.
        let quotedArgs = arguments.map { shellQuote($0) }.joined(separator: " ")
        let fullCommand = quotedArgs.isEmpty ? command : "\(command) \(quotedArgs)"

        let shell = resolvedShell()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        // -l  → login shell (loads profile, sets PATH etc.)
        // -c  → execute the following command string
        process.arguments = ["-l", "-c", fullCommand]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError  = stderrPipe

        // Propagate the current environment so sandbox entitlements survive.
        process.environment = ProcessInfo.processInfo.environment

        return try await withCheckedThrowingContinuation { continuation in
            // Timeout watchdog.
            let timeoutWork = DispatchWorkItem {
                if process.isRunning {
                    process.terminate()
                }
                continuation.resume(throwing: ShellError.timeout)
            }
            DispatchQueue.global().asyncAfter(
                deadline: .now() + timeout,
                execute: timeoutWork
            )

            process.terminationHandler = { proc in
                timeoutWork.cancel()

                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""

                let exitCode = proc.terminationStatus

                guard exitCode == 0 else {
                    // 127 is the POSIX "command not found" exit code.
                    if exitCode == 127 {
                        continuation.resume(throwing: ShellError.commandNotFound(command))
                    } else {
                        continuation.resume(
                            throwing: ShellError.executionFailed(
                                exitCode: exitCode,
                                stderr: stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                            )
                        )
                    }
                    return
                }

                continuation.resume(
                    returning: stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }

            do {
                try process.run()
            } catch {
                timeoutWork.cancel()
                // Likely the shell binary itself is missing — highly unusual.
                continuation.resume(throwing: ShellError.commandNotFound(shell))
            }
        }
    }

    // MARK: - Private helpers

    /// Returns the shell binary path from the SHELL environment variable,
    /// falling back to `/bin/zsh` (the default shell on macOS 10.15+).
    private static func resolvedShell() -> String {
        ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    }

    /// Wraps `s` in single quotes, escaping any embedded single quotes.
    /// This is safe for arbitrary strings passed as shell arguments.
    private static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
