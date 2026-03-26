import SwiftUI

// MARK: - PATInputView

/// A SwiftUI sheet for entering a Personal Access Token (PAT) for services
/// that use token-based authentication (e.g. GitHub Copilot).
///
/// Presents contextual guidance on the required token scopes and a
/// direct link to the service's token-creation page. The caller supplies
/// `onSubmit` and `onCancel` closures; this view holds no business logic.
struct PATInputView: View {

    // MARK: Properties

    /// The service this PAT belongs to.
    let service: ServiceType

    /// Called with the trimmed token string when the user taps "Save".
    let onSubmit: (String) -> Void

    /// Called when the user dismisses the sheet without saving.
    let onCancel: () -> Void

    // MARK: State

    @State private var token: String = ""
    @State private var isRevealed: Bool = false
    @FocusState private var fieldFocused: Bool

    // MARK: Computed helpers

    private var trimmedToken: String { token.trimmingCharacters(in: .whitespaces) }
    private var canSubmit:    Bool   { !trimmedToken.isEmpty }

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            headerSection

            // Token input
            tokenInputSection

            // Required scopes & link
            scopesSection

            Spacer()

            // Action buttons
            actionButtons
        }
        .padding(24)
        .frame(minWidth: 440, minHeight: 300)
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

                Text("Enter a Personal Access Token to enable usage tracking.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var tokenInputSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Personal Access Token")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                Group {
                    if isRevealed {
                        TextField(tokenPlaceholder, text: $token)
                            .focused($fieldFocused)
                    } else {
                        SecureField(tokenPlaceholder, text: $token)
                            .focused($fieldFocused)
                    }
                }
                .font(.system(size: 13, design: .monospaced))
                .textFieldStyle(.roundedBorder)
                .onSubmit { if canSubmit { onSubmit(trimmedToken) } }

                Button {
                    isRevealed.toggle()
                } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(isRevealed ? "Hide token" : "Reveal token")
            }
        }
    }

    @ViewBuilder
    private var scopesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Required permissions")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(requiredScopes, id: \.self) { scope in
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(service.color)
                        Text(scope)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.primary)
                    }
                }
            }

            if let createURL = tokenCreationURL {
                Link(destination: createURL) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 11))
                        Text("Create token for \(service.displayName)")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(service.color)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.08))
        )
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
                onSubmit(trimmedToken)
            }
            .keyboardShortcut(.return, modifiers: [])
            .disabled(!canSubmit)
            .buttonStyle(.borderedProminent)
            .tint(service.color)
        }
    }

    // MARK: Service-specific metadata

    private var tokenPlaceholder: String {
        switch service {
        case .copilot: return "ghp_xxxxxxxxxxxxxxxxxxxx"
        default:       return "Paste your personal access token here"
        }
    }

    private var requiredScopes: [String] {
        switch service {
        case .copilot:
            return [
                "copilot (read)",
                "read:org (optional, for org-level usage)",
            ]
        default:
            return ["read access to usage data"]
        }
    }

    private var tokenCreationURL: URL? {
        switch service {
        case .copilot:
            return URL(string: "https://github.com/settings/tokens/new?scopes=copilot")
        default:
            return nil
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("GitHub Copilot PAT") {
    PATInputView(
        service: .copilot,
        onSubmit: { token in print("Submitted: \(token)") },
        onCancel: { print("Cancelled") }
    )
}
#endif
