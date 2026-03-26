import SwiftUI

// MARK: - APIKeyInputView

/// A SwiftUI sheet for entering an API key for services that use key-based
/// authentication (e.g. Google Gemini, Z.ai Coding Plan).
///
/// The view validates that the key is non-empty before enabling submission.
/// The caller supplies `onSubmit` and `onCancel` closures; this view is
/// purely presentational and holds no business logic.
struct APIKeyInputView: View {

    // MARK: Properties

    /// The service this API key belongs to (drives display name and branding).
    let service: ServiceType

    /// Called with the trimmed key string when the user taps "Save".
    let onSubmit: (String) -> Void

    /// Called when the user dismisses the sheet without saving.
    let onCancel: () -> Void

    // MARK: State

    @State private var apiKey: String = ""
    @State private var isRevealed: Bool = false
    @FocusState private var fieldFocused: Bool

    // MARK: Computed helpers

    private var trimmedKey: String { apiKey.trimmingCharacters(in: .whitespaces) }
    private var canSubmit:  Bool   { !trimmedKey.isEmpty }

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            headerSection

            // Input field
            keyInputSection

            // Helper text
            helperText

            Spacer()

            // Action buttons
            actionButtons
        }
        .padding(24)
        .frame(minWidth: 400, minHeight: 260)
        .onAppear { fieldFocused = true }
    }

    // MARK: Subviews

    @ViewBuilder
    private var headerSection: some View {
        HStack(spacing: 10) {
            Image(systemName: service.iconSystemName)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(service.color)

            VStack(alignment: .leading, spacing: 2) {
                Text("Connect \(service.displayName)")
                    .font(.system(size: 15, weight: .semibold))

                Text("Enter your API key to enable usage tracking.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var keyInputSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("API Key")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                Group {
                    if isRevealed {
                        TextField("Paste your API key here", text: $apiKey)
                            .focused($fieldFocused)
                    } else {
                        SecureField("Paste your API key here", text: $apiKey)
                            .focused($fieldFocused)
                    }
                }
                .font(.system(size: 13, design: .monospaced))
                .textFieldStyle(.roundedBorder)
                .onSubmit { if canSubmit { onSubmit(trimmedKey) } }

                Button {
                    isRevealed.toggle()
                } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(isRevealed ? "Hide key" : "Reveal key")
            }
        }
    }

    @ViewBuilder
    private var helperText: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch service {
            case .gemini:
                Label(
                    "Get your API key from Google AI Studio (aistudio.google.com).",
                    systemImage: "info.circle"
                )
            case .zai:
                Label(
                    "Get your API key from the Z.ai developer console.",
                    systemImage: "info.circle"
                )
            default:
                Label(
                    "Get your API key from the \(service.displayName) developer settings.",
                    systemImage: "info.circle"
                )
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.tertiary)
    }

    @ViewBuilder
    private var actionButtons: some View {
        HStack {
            Button("Cancel", role: .cancel) {
                onCancel()
            }
            .keyboardShortcut(.escape, modifiers: [])

            Spacer()

            Button("Save") {
                onSubmit(trimmedKey)
            }
            .keyboardShortcut(.return, modifiers: [])
            .disabled(!canSubmit)
            .buttonStyle(.borderedProminent)
            .tint(service.color)
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Gemini API Key") {
    APIKeyInputView(
        service: .gemini,
        onSubmit: { key in print("Submitted: \(key)") },
        onCancel: { print("Cancelled") }
    )
}

#Preview("Z.ai API Key") {
    APIKeyInputView(
        service: .zai,
        onSubmit: { key in print("Submitted: \(key)") },
        onCancel: { print("Cancelled") }
    )
}
#endif
