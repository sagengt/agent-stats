import SwiftUI

// MARK: - ProvidersSettingsTab

/// Lists every `ServiceType` and the accounts registered under each service.
///
/// For each service the user can:
/// - View registered accounts with their labels.
/// - Edit an account label inline.
/// - Remove an account.
/// - Add a new account (triggers the appropriate auth flow).
struct ProvidersSettingsTab: View {

    @EnvironmentObject var authCoordinator: AuthCoordinator
    @EnvironmentObject var viewModel: UsageViewModel

    // MARK: State

    @State private var accounts: [RegisteredAccount] = []
    @State private var editingKey: AccountKey? = nil
    @State private var editingLabel: String = ""
    @State private var isLoading = false

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Instruction banner
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.blue)
                Text("Add accounts to track usage across AI coding services.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.blue.opacity(0.06))

            Divider()

            // Service list
            if isLoading {
                ProgressView("Loading accounts…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(ServiceType.allCases) { service in
                            ServiceProviderSection(
                                service: service,
                                accounts: accounts.filter { $0.key.serviceType == service },
                                editingKey: $editingKey,
                                editingLabel: $editingLabel,
                                onAdd: { addAccount(for: service) },
                                onRemove: { key in removeAccount(key) },
                                onSaveLabel: { key, label in saveLabel(key: key, label: label) }
                            )

                            Divider()
                                .padding(.leading, 16)
                        }
                    }
                }
            }
        }
        .task { await loadAccounts() }
        .onChange(of: viewModel.lastRefreshedAt) { _, _ in
            Task { await loadAccounts() }
        }
        .onChange(of: authCoordinator.activationCount) { _, _ in
            Task {
                await loadAccounts()
                // Trigger a refresh so the new account's data is fetched immediately.
                viewModel.refresh()
            }
        }
        .onChange(of: authCoordinator.isAuthenticating) { _, isAuth in
            if !isAuth {
                Task { await loadAccounts() }
            }
        }
        .sheet(isPresented: $authCoordinator.showingAPIKeyInput) {
            if let service = authCoordinator.apiKeyInputService {
                APIKeySheet(service: service) { key in
                    Task { await authCoordinator.submitAPIKey(key, for: service) }
                } onCancel: {
                    authCoordinator.showingAPIKeyInput = false
                    authCoordinator.apiKeyInputService = nil
                }
            }
        }
    }

    // MARK: Actions

    private func loadAccounts() async {
        isLoading = true
        accounts = await viewModel.accountManager.allAccounts()
        isLoading = false
    }

    private func addAccount(for service: ServiceType) {
        Task {
            let method = ServiceCatalog.authMethod(for: service)
            await authCoordinator.authenticate(service: service, method: method)
            await loadAccounts()
        }
    }

    private func removeAccount(_ key: AccountKey) {
        Task {
            await viewModel.accountManager.unregister(key)
            await loadAccounts()
        }
    }

    private func saveLabel(key: AccountKey, label: String) {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task {
            await viewModel.accountManager.updateLabel(for: key, label: trimmed)
            await loadAccounts()
        }
        editingKey = nil
    }
}

// MARK: - ServiceProviderSection

/// One row-group for a single service type: a header + account rows.
private struct ServiceProviderSection: View {

    let service: ServiceType
    let accounts: [RegisteredAccount]
    @Binding var editingKey: AccountKey?
    @Binding var editingLabel: String
    let onAdd: () -> Void
    let onRemove: (AccountKey) -> Void
    let onSaveLabel: (AccountKey, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Service header row
            HStack(spacing: 10) {
                service.iconImage
                    .foregroundStyle(service.color)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(service.displayName)
                        .font(.system(size: 13, weight: .semibold))
                    Text(authMethodDescription(for: service))
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                // Add account button
                Button {
                    onAdd()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(service.color)
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
                .help("Add \(service.displayName) account")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            // Registered accounts
            if !accounts.isEmpty {
                ForEach(accounts) { account in
                    AccountRow(
                        account: account,
                        isEditing: editingKey == account.key,
                        editingLabel: editingKey == account.key ? $editingLabel : .constant(""),
                        serviceColor: service.color,
                        onEditStart: {
                            editingKey = account.key
                            editingLabel = account.label
                        },
                        onEditSave: {
                            onSaveLabel(account.key, editingLabel)
                        },
                        onEditCancel: {
                            editingKey = nil
                        },
                        onRemove: {
                            onRemove(account.key)
                        }
                    )
                }
            } else {
                Text("No accounts — tap + to add one.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 46)
                    .padding(.bottom, 8)
            }
        }
    }

    private func authMethodDescription(for service: ServiceType) -> String {
        switch ServiceCatalog.authMethod(for: service) {
        case .oauthWebView:        return "Sign in via web"
        case .personalAccessToken: return "Personal access token"
        case .apiKey:              return "API key"
        case .none:                return "No authentication required"
        case .importFromCLI:       return "Import from CLI"
        }
    }
}

// MARK: - AccountRow

/// A single registered account with inline label editing and a remove button.
private struct AccountRow: View {

    let account: RegisteredAccount
    let isEditing: Bool
    @Binding var editingLabel: String
    let serviceColor: Color
    let onEditStart: () -> Void
    let onEditSave: () -> Void
    let onEditCancel: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // Indent indicator
            Capsule()
                .fill(serviceColor.opacity(0.3))
                .frame(width: 3, height: 24)
                .padding(.leading, 30)

            if isEditing {
                TextField("Account label", text: $editingLabel)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .onSubmit { onEditSave() }

                Button("Save") { onEditSave() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                Button("Cancel") { onEditCancel() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.label)
                        .font(.system(size: 12, weight: .medium))
                    Text("Added \(account.registeredAt, style: .date)")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                // Edit label button
                Button {
                    onEditStart()
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Edit label")

                // Remove button
                Button {
                    onRemove()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("Remove account")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.03))
    }
}

// MARK: - APIKeySheet

private struct APIKeySheet: View {
    let service: ServiceType
    var title: String = "API Key"
    var placeholder: String = "Enter your API key..."
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    @State private var key = ""

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                service.iconImage
                    .foregroundStyle(service.color)
                    .font(.title2)
                Text("Add \(service.displayName) \(title)")
                    .font(.headline)
            }

            Text("Enter your \(title.lowercased()) to connect \(service.displayName).")
                .font(.callout)
                .foregroundStyle(.secondary)

            SecureField(placeholder, text: $key)
                .textFieldStyle(.roundedBorder)
                .frame(width: 350)

            HStack {
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Connect") {
                    onSubmit(key)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Providers Settings") {
    ProvidersSettingsTab()
        .frame(width: 500, height: 400)
}
#endif
