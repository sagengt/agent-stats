import SwiftUI

// MARK: - MenuBarDisplayMode

/// Controls how usage data is presented in the macOS menu bar label area.
enum MenuBarDisplayMode: String, CaseIterable, Identifiable {
    /// Shows the service name + highest quota percentage as text, e.g. "Claude 75%".
    case label

    /// Cycles through services with a compact animated stacked bar.
    case carousel

    /// Shows only the app icon tinted by the highest usage colour.
    case compact

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .label:    return "Label"
        case .carousel: return "Carousel"
        case .compact:  return "Compact"
        }
    }

    var iconSystemName: String {
        switch self {
        case .label:    return "textformat"
        case .carousel: return "play.square.stack"
        case .compact:  return "square.fill"
        }
    }

    var description: String {
        switch self {
        case .label:
            return "Shows service name and usage percentage"
        case .carousel:
            return "Cycles through services with animated bars"
        case .compact:
            return "Icon only with colour indicator"
        }
    }
}

// MARK: - MenuBarDisplayModeKey

/// `AppStorage`-compatible `UserDefaults` key for the persisted display mode.
enum MenuBarDisplayModeKey {
    static let userDefaultsKey = "agentstats.menubar.displayMode"

    static func load() -> MenuBarDisplayMode {
        let raw = UserDefaults.standard.string(forKey: userDefaultsKey) ?? ""
        return MenuBarDisplayMode(rawValue: raw) ?? .label
    }

    static func save(_ mode: MenuBarDisplayMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: userDefaultsKey)
    }
}

// MARK: - MenuBarDisplayModePicker

/// An inline picker used in both the Settings tab and the menu bar content
/// dropdown so the user can switch display modes without opening Settings.
struct MenuBarDisplayModePicker: View {

    @Binding var selection: MenuBarDisplayMode

    var body: some View {
        Picker("Menu Bar Style", selection: $selection) {
            ForEach(MenuBarDisplayMode.allCases) { mode in
                Label(mode.displayName, systemImage: mode.iconSystemName)
                    .tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: selection) { _, newValue in
            MenuBarDisplayModeKey.save(newValue)
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Display Mode Picker") {
    @Previewable @State var mode: MenuBarDisplayMode = .label
    MenuBarDisplayModePicker(selection: $mode)
        .padding()
        .frame(width: 320)
}
#endif
