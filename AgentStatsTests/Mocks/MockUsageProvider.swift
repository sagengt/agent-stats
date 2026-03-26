import Foundation
@testable import AgentStats

// MARK: - MockQuotaProvider

struct MockQuotaProvider: QuotaWindowProvider {
    let account: AccountKey
    var serviceType: ServiceType { account.serviceType }
    var configured: Bool = true
    var windows: [QuotaWindow] = []
    var error: Error?

    func isConfigured() async -> Bool { configured }

    func fetchQuotaWindows() async throws -> [QuotaWindow] {
        if let error { throw error }
        return windows
    }
}

// MARK: - MockTokenProvider

struct MockTokenProvider: TokenUsageProvider {
    let account: AccountKey
    var serviceType: ServiceType { account.serviceType }
    var configured: Bool = true
    var summary: TokenUsageSummary?
    var error: Error?

    func isConfigured() async -> Bool { configured }

    func fetchTokenUsage() async throws -> TokenUsageSummary {
        if let error { throw error }
        return summary ?? TokenUsageSummary(
            totalTokens: 0,
            inputTokens: 0,
            outputTokens: 0,
            costUSD: nil,
            period: .today
        )
    }
}

// MARK: - MockActivityProvider

struct MockActivityProvider: SessionActivityProvider {
    let account: AccountKey
    var serviceType: ServiceType { account.serviceType }
    var configured: Bool = true
    var activity: SessionActivity?
    var error: Error?

    func isConfigured() async -> Bool { configured }

    func fetchSessionActivity() async throws -> SessionActivity {
        if let error { throw error }
        return activity ?? SessionActivity(
            activeSessions: 0,
            totalDurationMinutes: 0,
            requestCount: 0,
            lastActiveAt: nil
        )
    }
}
