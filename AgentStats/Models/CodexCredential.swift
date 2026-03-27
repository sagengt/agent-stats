import Foundation

struct CodexCredential: Sendable, Codable {
    let accessToken: String
    let refreshToken: String?
    let chatgptAccountId: String
    let email: String?
    let expiresAt: Date?

    var isExpired: Bool {
        guard let exp = expiresAt else { return false }
        return exp < Date()
    }

    /// Parse from ~/.codex/auth.json
    static func fromAuthJson() -> CodexCredential? {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/auth.json").path
        guard let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = json["tokens"] as? [String: Any],
              let accessToken = tokens["access_token"] as? String else { return nil }

        let refreshToken = tokens["refresh_token"] as? String
        let accountId = tokens["account_id"] as? String ?? ""

        // Decode JWT to get email and exp
        let (email, exp) = decodeJWT(accessToken)

        return CodexCredential(
            accessToken: accessToken,
            refreshToken: refreshToken,
            chatgptAccountId: accountId.isEmpty ? (decodeJWTAccountId(accessToken) ?? UUID().uuidString) : accountId,
            email: email,
            expiresAt: exp
        )
    }

    private static func decodeJWT(_ token: String) -> (email: String?, exp: Date?) {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return (nil, nil) }
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return (nil, nil) }

        let email = (payload["https://api.openai.com/profile"] as? [String: Any])?["email"] as? String
            ?? payload["email"] as? String
        let exp = (payload["exp"] as? Double).map { Date(timeIntervalSince1970: $0) }
        return (email, exp)
    }

    private static func decodeJWTAccountId(_ token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (payload["https://api.openai.com/auth"] as? [String: Any])?["chatgpt_account_id"] as? String
    }
}
