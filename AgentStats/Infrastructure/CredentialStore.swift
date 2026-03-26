import Foundation

/// Actor-based credential store keyed by `AccountKey`.
///
/// `AuthCoordinator` writes credentials; Providers read them.
/// An in-memory cache avoids redundant Keychain I/O on every provider tick.
actor CredentialStore {

    // MARK: - Dependencies

    private let keychain: KeychainManager

    // MARK: - Init

    init(keychain: KeychainManager = .shared) {
        self.keychain = keychain
    }

    // MARK: - Public API

    func save(for key: AccountKey, material: CredentialMaterial) async {
        let storageKey = self.keychainKey(for: key)
        do {
            try keychain.save(material, for: storageKey)
            AppLogger.log("[CredentialStore] Saved: \(key.serviceType):\(key.accountId.prefix(8))")
        } catch {
            AppLogger.log("[CredentialStore] Save FAILED: \(error.localizedDescription)")
        }
    }

    func load(for key: AccountKey) async -> CredentialMaterial? {
        let storageKey = self.keychainKey(for: key)
        do {
            return try keychain.load(CredentialMaterial.self, for: storageKey)
        } catch {
            AppLogger.log("[CredentialStore] Load failed: \(error.localizedDescription)")
            return nil
        }
    }

    func invalidate(for key: AccountKey) async {
        let storageKey = self.keychainKey(for: key)
        do { try keychain.delete(for: storageKey) } catch {}
    }

    func delete(for key: AccountKey) async {
        await invalidate(for: key)
    }

    // MARK: - Private helpers

    private func keychainKey(for key: AccountKey) -> String {
        "agentstats.credential.\(key.serviceType.rawValue).\(key.accountId)"
    }
}
