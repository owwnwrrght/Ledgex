import Foundation

// Payment provider types supported by the app
enum PaymentProvider: String, Codable, CaseIterable {
    case venmo = "Venmo"
    case manual = "Manual Payment"

    var icon: String {
        switch self {
        case .venmo: return "venmo"
        case .manual: return "creditcard"
        }
    }

    var displayName: String {
        return self.rawValue
    }

    var requiresSDK: Bool {
        switch self {
        case .venmo: return true
        case .manual: return false
        }
    }
}

// Payment transaction status
enum PaymentStatus: String, Codable {
    case pending = "Pending"
    case processing = "Processing"
    case completed = "Completed"
    case failed = "Failed"
    case cancelled = "Cancelled"
    case refunded = "Refunded"
}

// Payment transaction record
struct PaymentTransaction: Identifiable, Codable {
    var id = UUID()
    var settlementId: UUID
    var provider: PaymentProvider
    var status: PaymentStatus
    var amount: Decimal
    var currency: Currency
    var fromUserId: UUID
    var toUserId: UUID
    var externalTransactionId: String?
    var errorMessage: String?
    var createdAt: Date
    var updatedAt: Date
    var completedAt: Date?

    init(settlementId: UUID, provider: PaymentProvider, amount: Decimal, currency: Currency, fromUserId: UUID, toUserId: UUID) {
        self.settlementId = settlementId
        self.provider = provider
        self.status = .pending
        self.amount = amount
        self.currency = currency
        self.fromUserId = fromUserId
        self.toUserId = toUserId
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// User's linked payment accounts
struct LinkedPaymentAccount: Identifiable, Codable {
    var id = UUID()
    var provider: PaymentProvider
    var accountIdentifier: String // email, phone, username, etc.
    var displayName: String?
    var isVerified: Bool
    var linkedAt: Date
    var lastUsed: Date?
    var preferenceOrder: Int? // Lower number = higher preference (1 is most preferred)

    var formattedIdentifier: String {
        switch provider {
        case .venmo:
            // Username format
            return accountIdentifier.hasPrefix("@") ? accountIdentifier : "@\(accountIdentifier)"
        case .manual:
            return "Manual"
        }
    }
}
