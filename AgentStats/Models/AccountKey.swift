import Foundation

struct AccountKey: Hashable, Sendable, Codable {
    let serviceType: ServiceType
    let accountId: String  // UUID string

    init(serviceType: ServiceType, accountId: String = UUID().uuidString) {
        self.serviceType = serviceType
        self.accountId = accountId
    }
}
