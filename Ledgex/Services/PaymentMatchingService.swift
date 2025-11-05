import Foundation

// MARK: - Payment Match Result (Legacy - Not Used)
// This service is no longer used - Venmo username matching happens in PaymentService
struct PaymentMatch: Identifiable, Equatable {
    let id = UUID()
    let provider: PaymentProvider

    static func == (lhs: PaymentMatch, rhs: PaymentMatch) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - Payment Matching Service (Legacy - Not Used)
// This service is no longer used - Venmo username matching happens in PaymentService
class PaymentMatchingService {
    static let shared = PaymentMatchingService()

    private init() {}
}
