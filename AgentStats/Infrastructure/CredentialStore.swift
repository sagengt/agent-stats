import Foundation

/// Actor-based credential store.
///
/// AuthCoordinator writes credentials; Providers read them.
/// An in-memory cache avoids redundant Keychain I/O on every provider tick.
actor CredentialStore {

    // MARK: - Dependencies

    private let keychain: KeychainManager

    // MARK: - State

    /// In-memory cache keyed by ServiceType.
    private var cache: [ServiceType: CredentialMaterial] = [:]

    // MARK: - Init

    init(keychain: KeychainManager = .shared) {
        self.keychain = keychain
    }

    // MARK: - Public API

    /// Persists `material` to both the in-memory cache and Keychain.
    func save(for service: ServiceType, material: CredentialMaterial) async {
        cache[service] = material
        let key = keychainKey(for: service)
        do {
            try keychain.save(material, for: key)
        } catch {
            // Keychain persistence failure is non-fatal; cache remains valid for the session.
            // The credential will be re-entered on next launch if the process restarts.
            print("[CredentialStore] Keychain save failed for \(service.rawValue): \(error.localizedDescription)")
        }
    }

    /// Returns the credential for `service`, loading from Keychain on first access.
    /// Returns `nil` if no credential has been stored.
    func load(for service: ServiceType) async -> CredentialMaterial? {
        if let cached = cache[service] {
            return cached
        }

        let key = keychainKey(for: service)
        do {
            if let material = try keychain.load(CredentialMaterial.self, for: key) {
                cache[service] = material
                return material
            }
        } catch {
            print("[CredentialStore] Keychain load failed for \(service.rawValue): \(error.localizedDescription)")
        }
        return nil
    }

    /// Removes the credential for `service` from both the cache and Keychain.
    func invalidate(for service: ServiceType) async {
        cache.removeValue(forKey: service)
        let key = keychainKey(for: service)
        do {
            try keychain.delete(for: key)
        } catch {
            print("[CredentialStore] Keychain delete failed for \(service.rawValue): \(error.localizedDescription)")
        }
    }

    // MARK: - Private helpers

    private func keychainKey(for service: ServiceType) -> String {
        "agentstats.credential.\(service.rawValue)"
    }
}
