import Foundation

/// Credential store backed entirely by UserDefaults.
///
/// Each credential is stored under its own key in UserDefaults.
/// No in-memory cache — every read goes to UserDefaults, every write
/// goes to UserDefaults. This eliminates all cache coherency issues.
///
/// Key format: "cred2.<serviceType>.<accountId>"
/// (prefix "cred2" avoids collision with previous implementations)
actor CredentialStore {

    static let shared = CredentialStore()

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(keychain: KeychainManager = .shared) {
        AppLogger.log("[CredentialStore] Initialized")
    }

    func save(for key: AccountKey, material: CredentialMaterial) async {
        let udKey = storageKey(for: key)
        do {
            let data = try encoder.encode(material)
            UserDefaults.standard.set(data, forKey: udKey)
            // Force synchronize to ensure write is committed
            UserDefaults.standard.synchronize()
            // Verify
            let check = UserDefaults.standard.data(forKey: udKey)
            AppLogger.log("[CredentialStore] Saved \(key.serviceType):\(key.accountId.prefix(8)) (\(data.count)b, verify=\(check?.count ?? -1)) key=\(udKey)")
        } catch {
            AppLogger.log("[CredentialStore] Encode failed: \(error)")
        }
    }

    func load(for key: AccountKey) async -> CredentialMaterial? {
        let udKey = storageKey(for: key)
        guard let data = UserDefaults.standard.data(forKey: udKey) else {
            return nil
        }
        do {
            return try decoder.decode(CredentialMaterial.self, from: data)
        } catch {
            AppLogger.log("[CredentialStore] Decode failed for \(udKey): \(error)")
            return nil
        }
    }

    func invalidate(for key: AccountKey) async {
        let udKey = storageKey(for: key)
        UserDefaults.standard.removeObject(forKey: udKey)
        UserDefaults.standard.synchronize()
    }

    func delete(for key: AccountKey) async {
        await invalidate(for: key)
    }

    private func storageKey(for key: AccountKey) -> String {
        "cred2.\(key.serviceType.rawValue).\(key.accountId)"
    }
}
