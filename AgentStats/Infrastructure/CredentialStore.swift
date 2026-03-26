import Foundation

/// Actor-based credential store keyed by `AccountKey`.
///
/// `AuthCoordinator` writes credentials; Providers read them.
/// An in-memory cache avoids redundant Keychain I/O on every provider tick.
actor CredentialStore {

    // MARK: - Dependencies

    private let keychain: KeychainManager

    // MARK: - State

    /// In-memory cache keyed by `AccountKey`.
    private var cache: [AccountKey: CredentialMaterial] = [:]

    // MARK: - Init

    init(keychain: KeychainManager = .shared) {
        self.keychain = keychain
    }

    // MARK: - Public API

    /// Persists `material` to both the in-memory cache and Keychain.
    func save(for key: AccountKey, material: CredentialMaterial) async {
        cache[key] = material
        let keychainKey = self.keychainKey(for: key)
        do {
            try keychain.save(material, for: keychainKey)
        } catch {
            // Keychain persistence failure is non-fatal; cache remains valid for the session.
            // The credential will be re-entered on next launch if the process restarts.
            print("[CredentialStore] Keychain save failed for \(key): \(error.localizedDescription)")
        }
    }

    /// Returns the credential for `key`, loading from Keychain on first access.
    /// Returns `nil` if no credential has been stored.
    func load(for key: AccountKey) async -> CredentialMaterial? {
        if let cached = cache[key] {
            return cached
        }

        let keychainKey = self.keychainKey(for: key)
        do {
            if let material = try keychain.load(CredentialMaterial.self, for: keychainKey) {
                cache[key] = material
                return material
            }
        } catch {
            print("[CredentialStore] Keychain load failed for \(key): \(error.localizedDescription)")
        }
        return nil
    }

    /// Removes the credential for `key` from both the cache and Keychain.
    func invalidate(for key: AccountKey) async {
        cache.removeValue(forKey: key)
        let keychainKey = self.keychainKey(for: key)
        do {
            try keychain.delete(for: keychainKey)
        } catch {
            print("[CredentialStore] Keychain delete failed for \(key): \(error.localizedDescription)")
        }
    }

    /// Permanently deletes the credential for `key` from both the cache and Keychain.
    ///
    /// Semantically identical to `invalidate`; provided as an explicit deletion
    /// API for the account-removal flow to make intent clear at call sites.
    func delete(for key: AccountKey) async {
        await invalidate(for: key)
    }

    // MARK: - Private helpers

    private func keychainKey(for key: AccountKey) -> String {
        "agentstats.credential.\(key.serviceType.rawValue).\(key.accountId)"
    }
}
