import Foundation

struct RegisteredAccount: Sendable, Codable, Identifiable {
    let key: AccountKey
    var label: String
    let registeredAt: Date
    var id: AccountKey { key }
}

struct TombstonedAccount: Sendable, Codable {
    let key: AccountKey
    let lastKnownLabel: String
    let deletedAt: Date
}

struct AccountSnapshot: Sendable, Codable {
    var provisionalAccounts: [RegisteredAccount] = []
    var activeAccounts: [RegisteredAccount] = []
    var tombstoned: [TombstonedAccount] = []
}

enum AccountSnapshotLoader {
    private static let key = "agentstats.accounts"

    static func loadSync() -> AccountSnapshot {
        guard let data = UserDefaults.standard.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(AccountSnapshot.self, from: data) else {
            // Check for legacy migration
            var snapshot = AccountSnapshot()
            migrateLegacyAccounts(into: &snapshot)
            // Discard any orphan provisionals from previous session
            snapshot.provisionalAccounts.removeAll()
            saveSync(snapshot)
            return snapshot
        }
        // Discard orphan provisionals on every launch
        var cleaned = snapshot
        cleaned.provisionalAccounts.removeAll()
        if cleaned.provisionalAccounts.count != snapshot.provisionalAccounts.count {
            saveSync(cleaned)
        }
        return cleaned
    }

    static func saveSync(_ snapshot: AccountSnapshot) {
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private static func migrateLegacyAccounts(into snapshot: inout AccountSnapshot) {
        let keychain = KeychainManager.shared
        for service in ServiceType.allCases {
            let legacyKey = "agentstats.credential.\(service.rawValue)"
            if let _: CredentialMaterial = try? keychain.load(CredentialMaterial.self, for: legacyKey) {
                let accountKey = AccountKey(serviceType: service)
                let account = RegisteredAccount(
                    key: accountKey,
                    label: "\(service.displayName) (migrated)",
                    registeredAt: Date()
                )
                snapshot.activeAccounts.append(account)
                // Re-save credential under new AccountKey-scoped key
                let newKey = "agentstats.credential.\(service.rawValue).\(accountKey.accountId)"
                if let cred: CredentialMaterial = try? keychain.load(CredentialMaterial.self, for: legacyKey) {
                    try? keychain.save(cred, for: newKey)
                }
                try? keychain.delete(for: legacyKey)
            }
        }
    }
}
