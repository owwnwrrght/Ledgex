import Foundation

struct Settlement: Identifiable, Codable {
    let id = UUID()
    let from: Person
    let to: Person
    let amount: Decimal
    var isReceived: Bool = false

    // Payment integration fields
    var paymentTransactionId: UUID?
    var paymentProvider: PaymentProvider?
    var paymentStatus: PaymentStatus?
    var paymentInitiatedAt: Date?
    var paymentCompletedAt: Date?
    var externalTransactionId: String?

    var isPaymentInProgress: Bool {
        guard let status = paymentStatus else { return false }
        return status == .pending || status == .processing
    }

    var isPaidViaApp: Bool {
        return paymentStatus == .completed && paymentProvider != nil
    }

    var paymentDisplayText: String? {
        guard let provider = paymentProvider, let status = paymentStatus else {
            return nil
        }

        switch status {
        case .pending:
            return "Initiated via \(provider.displayName)"
        case .processing:
            return "Processing via \(provider.displayName)..."
        case .completed:
            return "Paid via \(provider.displayName)"
        case .failed:
            return "Payment failed"
        case .cancelled:
            return "Payment cancelled"
        case .refunded:
            return "Refunded"
        }
    }
}
