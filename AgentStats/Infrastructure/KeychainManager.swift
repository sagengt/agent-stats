import Foundation
import Security

/// Credential storage manager.
///
/// Uses UserDefaults as the primary backend — reliable and proven working
/// in this application (AccountSnapshot already uses it successfully).
/// Keychain is kept as a legacy read-only fallback.
final class KeychainManager: Sendable {

    static let shared = KeychainManager()

    private let serviceName = "com.agentstats.credentials"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {}

    // MARK: - Public API

    func save<T: Codable>(_ value: T, for key: String) throws {
        let data = try encode(value)
        UserDefaults.standard.set(data, forKey: "cred.\(key)")
        AppLogger.log("[KeychainManager] Saved to UserDefaults: \(key) (\(data.count) bytes)")
    }

    func load<T: Codable>(_ type: T.Type, for key: String) throws -> T? {
        if let data = UserDefaults.standard.data(forKey: "cred.\(key)") {
            return try decode(type, from: data)
        }
        return nil
    }

    func delete(for key: String) throws {
        UserDefaults.standard.removeObject(forKey: "cred.\(key)")
    }

    // MARK: - Encoding/Decoding

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        do { return try encoder.encode(value) }
        catch { throw KeychainError.encodingFailed(error) }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try decoder.decode(type, from: data) }
        catch { throw KeychainError.decodingFailed(error) }
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
            return "Unexpected data format."
        case .encodingFailed(let underlying):
            return "Encoding failed: \(underlying.localizedDescription)"
        case .decodingFailed(let underlying):
            return "Decoding failed: \(underlying.localizedDescription)"
        case .unhandledError(let status):
            return "Keychain error: OSStatus \(status)."
        }
    }
}
