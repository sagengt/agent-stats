import SwiftUI

/// AI coding service identifiers with associated display metadata.
enum ServiceType: String, Sendable, Codable, CaseIterable, Identifiable {
    case claude
    case codex
    case gemini
    case zai

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude:  return "Claude Code"
        case .codex:   return "ChatGPT Codex"
        case .gemini:  return "Google Gemini"
        case .zai:     return "Z.ai Coding Plan"
        }
    }

    var shortName: String {
        switch self {
        case .claude:  return "Claude"
        case .codex:   return "Codex"
        case .gemini:  return "Gemini"
        case .zai:     return "Z.ai"
        }
    }

    var color: Color {
        switch self {
        case .claude:  return Color(red: 0.20, green: 0.47, blue: 0.95)
        case .codex:   return Color(red: 0.16, green: 0.71, blue: 0.40)
        case .gemini:  return Color(red: 0.84, green: 0.18, blue: 0.18)
        case .zai:     return Color(red: 0.10, green: 0.70, blue: 0.65)
        }
    }

    var iconSystemName: String {
        switch self {
        case .claude:  return "sparkle"
        case .codex:   return "bubble.left.and.text.bubble.right"
        case .gemini:  return "star.leadinghalf.filled"
        case .zai:     return "bolt.circle"
        }
    }

    var iconImageName: String { "icon-\(rawValue)" }

    @ViewBuilder
    var iconImage: some View {
        if let nsImage = Self.loadIcon(named: iconImageName) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: iconSystemName)
        }
    }

    private static func loadIcon(named name: String) -> NSImage? {
        if let img = NSImage(named: name) { return img }
        if let url = Bundle.main.url(forResource: name, withExtension: "png") {
            return NSImage(contentsOf: url)
        }
        return nil
    }
}

// MARK: - Cookie domain allowlist

extension ServiceType {
    var allowedCookieDomains: [String] {
        switch self {
        case .claude: return ["claude.ai"]
        case .codex:  return ["chatgpt.com", "auth0.com", "openai.com"]
        default:      return []
        }
    }
}
