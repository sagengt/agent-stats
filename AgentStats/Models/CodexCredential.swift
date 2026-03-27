import Foundation

struct CodexCredential: Sendable, Codable {
    let accessToken: String
    let refreshToken: String?
    let chatgptAccountId: String
    let chatgptUserId: String      // user-level unique ID (different per user in same org)
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

        // Decode JWT to get email, exp, and user ID
        let (email, exp, userId) = decodeJWT(accessToken)

        return CodexCredential(
            accessToken: accessToken,
            refreshToken: refreshToken,
            chatgptAccountId: accountId.isEmpty ? (decodeJWTField(accessToken, field: "chatgpt_account_id") ?? UUID().uuidString) : accountId,
            chatgptUserId: userId ?? UUID().uuidString,
            email: email,
            expiresAt: exp
        )
    }

    private static func decodeJWT(_ token: String) -> (email: String?, exp: Date?, userId: String?) {
        guard let payload = decodeJWTPayload(token) else { return (nil, nil, nil) }
        let auth = payload["https://api.openai.com/auth"] as? [String: Any]
        let profile = payload["https://api.openai.com/profile"] as? [String: Any]
        let email = profile?["email"] as? String ?? payload["email"] as? String
        let exp = (payload["exp"] as? Double).map { Date(timeIntervalSince1970: $0) }
        let userId = auth?["chatgpt_user_id"] as? String
        return (email, exp, userId)
    }

    private static func decodeJWTField(_ token: String, field: String) -> String? {
        guard let payload = decodeJWTPayload(token) else { return nil }
        let auth = payload["https://api.openai.com/auth"] as? [String: Any]
        return auth?[field] as? String
    }

    private static func decodeJWTPayload(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
