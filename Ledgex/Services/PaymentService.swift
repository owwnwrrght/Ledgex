import Foundation
import UIKit
import Combine

// MARK: - Payment Service Errors
enum PaymentError: LocalizedError {
    case providerNotAvailable
    case accountNotLinked
    case invalidAmount
    case userCancelled
    case networkError
    case authenticationFailed
    case transactionFailed(String)
    case unsupportedProvider

    var errorDescription: String? {
        switch self {
        case .providerNotAvailable:
            return "Payment provider app is not installed"
        case .accountNotLinked:
            return "Please link your payment account first"
        case .invalidAmount:
            return "Invalid payment amount"
        case .userCancelled:
            return "Payment was cancelled"
        case .networkError:
            return "Network connection error"
        case .authenticationFailed:
            return "Payment authentication failed"
        case .transactionFailed(let message):
            return "Transaction failed: \(message)"
        case .unsupportedProvider:
            return "This payment provider is not supported yet"
        }
    }
}

// MARK: - Payment Result
struct PaymentResult {
    let success: Bool
    let transactionId: String?
    let error: PaymentError?
    let provider: PaymentProvider
}

// MARK: - Payment Service
@MainActor
class PaymentService: NSObject, ObservableObject {
    static let shared = PaymentService()

    @Published var isProcessingPayment = false
    @Published var lastPaymentResult: PaymentResult?

    private var profileManager = ProfileManager.shared
    private var firebaseManager = FirebaseManager.shared

    private override init() {
        super.init()
    }

    // MARK: - Provider Availability Checks

    func isProviderAvailable(_ provider: PaymentProvider) -> Bool {
        switch provider {
        case .venmo:
            // Check if Venmo app is installed
            if let url = URL(string: "venmo://") {
                return UIApplication.shared.canOpenURL(url)
            }
            return false
        case .manual:
            return true
        }
    }

    func availableProviders() -> [PaymentProvider] {
        return PaymentProvider.allCases.filter { isProviderAvailable($0) }
    }

    // MARK: - Venmo Username Checking

    /// Check if both payer and recipient have Venmo usernames linked
    func canPayViaVenmo(
        payer: UserProfile,
        recipientFirebaseUID: String?
    ) async -> (canPay: Bool, recipientUsername: String?) {
        // Check if payer has Venmo
        guard payer.hasVenmoLinked else {
            print("⚠️ Payer has no Venmo username linked")
            return (false, nil)
        }

        // Check if recipient has Venmo
        guard let recipientUID = recipientFirebaseUID else {
            print("⚠️ Recipient has no Firebase UID")
            return (false, nil)
        }

        do {
            guard let recipientProfile = try await firebaseManager.fetchUserProfile(byFirebaseUID: recipientUID) else {
                print("⚠️ Recipient profile not found")
                return (false, nil)
            }

            guard let recipientVenmo = recipientProfile.venmoUsername, !recipientVenmo.isEmpty else {
                print("⚠️ Recipient has no Venmo username linked")
                return (false, nil)
            }

            return (true, recipientVenmo)
        } catch {
            print("❌ Error checking recipient Venmo: \(error)")
            return (false, nil)
        }
    }

    // MARK: - Main Payment Flow

    func initiateVenmoPayment(
        settlement: Settlement,
        recipientVenmoUsername: String,
        currency: Currency
    ) async -> PaymentResult {
        isProcessingPayment = true
        defer { isProcessingPayment = false }

        // Validate amount
        guard settlement.amount > 0 else {
            return PaymentResult(success: false, transactionId: nil, error: .invalidAmount, provider: .venmo)
        }

        // Check if Venmo is available
        guard isProviderAvailable(.venmo) else {
            return PaymentResult(success: false, transactionId: nil, error: .providerNotAvailable, provider: .venmo)
        }

        // Process Venmo payment
        let result = await processVenmoPayment(
            settlement: settlement,
            recipientUsername: recipientVenmoUsername,
            currency: currency
        )

        lastPaymentResult = result

        // Log transaction
        if result.success {
            await recordPaymentTransaction(settlement: settlement, result: result, currency: currency)
        }

        return result
    }

    // MARK: - Venmo Deep Link Payment

    private func processVenmoPayment(
        settlement: Settlement,
        recipientUsername: String,
        currency: Currency
    ) async -> PaymentResult {
        // Prepare payment details
        let username = recipientUsername.replacingOccurrences(of: "@", with: "")
        let note = "Ledgex: \(settlement.from.name) → \(settlement.to.name)"
        let amountString = formattedVenmoAmount(from: settlement.amount)

        guard let amountString else {
            return PaymentResult(
                success: false,
                transactionId: nil,
                error: .transactionFailed("Invalid payment amount"),
                provider: .venmo
            )
        }

        // Construct the Venmo deep link using URLComponents to ensure proper encoding
        var components = URLComponents()
        components.scheme = "venmo"
        components.host = "paycharge"
        components.queryItems = [
            URLQueryItem(name: "txn", value: "pay"),
            URLQueryItem(name: "recipients", value: username),
            URLQueryItem(name: "amount", value: amountString),
            URLQueryItem(name: "note", value: note),
            URLQueryItem(name: "audience", value: "private")
        ]

        guard let venmoURL = components.url else {
            return PaymentResult(
                success: false,
                transactionId: nil,
                error: .transactionFailed("Unable to create Venmo payment link"),
                provider: .venmo
            )
        }

        // Check if Venmo is installed
        guard UIApplication.shared.canOpenURL(venmoURL) else {
            return PaymentResult(
                success: false,
                transactionId: nil,
                error: .providerNotAvailable,
                provider: .venmo
            )
        }

        // Open Venmo with pre-filled payment details
        let opened = await UIApplication.shared.open(venmoURL)

        if opened {
            // Generate a transaction ID for tracking
            // Note: This is a "fire and forget" - we won't get confirmation from Venmo
            let transactionId = UUID().uuidString

            print("✅ Venmo opened successfully")
            print("   Amount: \(amountString) \(currency.rawValue)")
            print("   Recipient: @\(username)")
            print("   Note: \(note)")

            return PaymentResult(
                success: true,
                transactionId: transactionId,
                error: nil,
                provider: .venmo
            )
        } else {
            return PaymentResult(
                success: false,
                transactionId: nil,
                error: .providerNotAvailable,
                provider: .venmo
            )
        }
    }

    private func formattedVenmoAmount(from amount: Decimal) -> String? {
        let number = NSDecimalNumber(decimal: amount)
        guard number.doubleValue > 0 else { return nil }

        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = false

        return formatter.string(from: number)
    }

    // MARK: - Transaction Recording

    private func recordPaymentTransaction(settlement: Settlement, result: PaymentResult, currency: Currency) async {
        var transaction = PaymentTransaction(
            settlementId: settlement.id,
            provider: result.provider,
            amount: settlement.amount,
            currency: currency, // Use settlement's currency
            fromUserId: settlement.from.id,
            toUserId: settlement.to.id
        )
        transaction.status = result.success ? .completed : .failed
        transaction.externalTransactionId = result.transactionId
        transaction.errorMessage = result.error?.localizedDescription
        transaction.updatedAt = Date()
        if result.success {
            transaction.completedAt = Date()
        }

        do {
            try await firebaseManager.savePaymentTransaction(transaction)
        } catch {
            print("❌ Failed to record payment transaction: \(error)")
        }
    }
}
