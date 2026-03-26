import SwiftUI

/// AI coding service identifiers with associated display metadata.
enum ServiceType: String, Sendable, Codable, CaseIterable, Identifiable {
    case claude
    case codex
    case gemini
    case copilot
    case cursor
    case opencode
    case zai

    var id: String { rawValue }

    /// Full display name shown in UI.
    var displayName: String {
        switch self {
        case .claude:    return "Claude Code"
        case .codex:     return "ChatGPT Codex"
        case .gemini:    return "Google Gemini"
        case .copilot:   return "GitHub Copilot"
        case .cursor:    return "Cursor"
        case .opencode:  return "OpenCode"
        case .zai:       return "Z.ai Coding Plan"
        }
    }

    /// Abbreviated name for compact UI contexts.
    var shortName: String {
        switch self {
        case .claude:    return "Claude"
        case .codex:     return "Codex"
        case .gemini:    return "Gemini"
        case .copilot:   return "Copilot"
        case .cursor:    return "Cursor"
        case .opencode:  return "OpenCode"
        case .zai:       return "Z.ai"
        }
    }

    /// Brand-representative SwiftUI color.
    var color: Color {
        switch self {
        case .claude:    return Color(red: 0.20, green: 0.47, blue: 0.95)   // Anthropic blue
        case .codex:     return Color(red: 0.16, green: 0.71, blue: 0.40)   // OpenAI green
        case .gemini:    return Color(red: 0.84, green: 0.18, blue: 0.18)   // Google red
        case .copilot:   return Color(red: 0.45, green: 0.45, blue: 0.50)   // GitHub gray
        case .cursor:    return Color(red: 0.55, green: 0.25, blue: 0.90)   // Cursor purple
        case .opencode:  return Color(red: 0.95, green: 0.50, blue: 0.10)   // OSS orange
        case .zai:       return Color(red: 0.10, green: 0.70, blue: 0.65)   // Z.ai teal
        }
    }

    /// SF Symbol name representing the service in system UI.
    var iconSystemName: String {
        switch self {
        case .claude:    return "sparkle"
        case .codex:     return "bubble.left.and.text.bubble.right"
        case .gemini:    return "star.leadinghalf.filled"
        case .copilot:   return "airplane.circle"
        case .cursor:    return "cursorarrow.rays"
        case .opencode:  return "chevron.left.forwardslash.chevron.right"
        case .zai:       return "bolt.circle"
        }
    }
}

// MARK: - Cookie domain allowlist

extension ServiceType {
    /// Domain substrings that are permitted when filtering cookies captured
    /// during the OAuth WebView login flow.
    ///
    /// Only cookies whose `domain` contains at least one of these strings are
    /// forwarded to `AuthCoordinator`; all others are discarded to minimise
    /// the attack surface and avoid storing credentials for unrelated sites.
    ///
    /// Services that do not use the OAuth WebView flow return an empty array,
    /// which causes the filter to discard all cookies (they will never appear
    /// in practice because the WebView is not shown for those services).
    var allowedCookieDomains: [String] {
        switch self {
        case .claude:
            return ["claude.ai"]
        case .codex:
            // chatgpt.com hosts the UI; auth0.com and openai.com handle SSO.
            return ["chatgpt.com", "auth0.com", "openai.com"]
        default:
            // Other services do not use the OAuth WebView in Phase 1.
            return []
        }
    }
}
