import Foundation
import Security

/// Thread-safe Keychain wrapper for persisting Codable values.
/// Uses kSecClassGenericPassword with a fixed service name.
final class KeychainManager: Sendable {

    static let shared = KeychainManager()

    private let serviceName = "com.agentstats.credentials"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {}

    // MARK: - Public API

    /// Encodes `value` as JSON and writes it to Keychain under `key`.
    /// Overwrites any existing item with the same key.
    func save<T: Codable>(_ value: T, for key: String) throws {
        let data = try encode(value)

        // Try update first; fall back to add if item does not exist yet.
        if try itemExists(for: key) {
            try updateItem(data: data, for: key)
        } else {
            try addItem(data: data, for: key)
        }
    }

    /// Loads and decodes a `T` value previously saved under `key`.
    /// Returns `nil` if no item exists for the key.
    func load<T: Codable>(_ type: T.Type, for key: String) throws -> T? {
        let query: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrService:      serviceName,
            kSecAttrAccount:      key,
            kSecReturnData:       true,
            kSecMatchLimit:       kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw KeychainError.unexpectedData
            }
            return try decode(type, from: data)

        case errSecItemNotFound:
            return nil

        default:
            throw KeychainError.unhandledError(status: status)
        }
    }

    /// Removes the Keychain item stored under `key`.
    /// Succeeds silently if the item does not exist.
    func delete(for key: String) throws {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: serviceName,
            kSecAttrAccount: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledError(status: status)
        }
    }

    // MARK: - Private helpers

    private func itemExists(for key: String) throws -> Bool {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: serviceName,
            kSecAttrAccount: key,
            kSecReturnData:  false
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        switch status {
        case errSecSuccess:      return true
        case errSecItemNotFound: return false
        default: throw KeychainError.unhandledError(status: status)
        }
    }

    private func addItem(data: Data, for key: String) throws {
        let attributes: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrService:      serviceName,
            kSecAttrAccount:      key,
            kSecValueData:        data,
            kSecAttrAccessible:   kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unhandledError(status: status)
        }
    }

    private func updateItem(data: Data, for key: String) throws {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: serviceName,
            kSecAttrAccount: key
        ]
        let attributes: [CFString: Any] = [
            kSecValueData: data
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        guard status == errSecSuccess else {
            throw KeychainError.unhandledError(status: status)
        }
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        do {
            return try encoder.encode(value)
        } catch {
            throw KeychainError.encodingFailed(error)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw KeychainError.decodingFailed(error)
        }
    }
}

// MARK: - KeychainError

enum KeychainError: Error, LocalizedError {
    case unexpectedData
    case encodingFailed(Error)
    case decodingFailed(Error)
    case unhandledError(status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .unexpectedData:
            return "Keychain returned data in an unexpected format."
        case .encodingFailed(let underlying):
            return "Failed to encode value for Keychain: \(underlying.localizedDescription)"
        case .decodingFailed(let underlying):
            return "Failed to decode value from Keychain: \(underlying.localizedDescription)"
        case .unhandledError(let status):
            return "Keychain operation failed with OSStatus \(status)."
        }
    }
}
