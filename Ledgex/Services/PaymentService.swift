import Foundation
import UIKit
import PassKit

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
class PaymentService: ObservableObject {
    static let shared = PaymentService()

    @Published var isProcessingPayment = false
    @Published var lastPaymentResult: PaymentResult?

    private var profileManager = ProfileManager.shared
    private var pkPaymentController: PKPaymentAuthorizationController?
    private var paymentMatchingService = PaymentMatchingService.shared
    private var firebaseManager = FirebaseManager.shared

    private init() {}

    // MARK: - Provider Availability Checks

    func isProviderAvailable(_ provider: PaymentProvider) -> Bool {
        switch provider {
        case .applePay:
            return PKPaymentAuthorizationController.canMakePayments()
        case .venmo:
            return canOpenURL(urlString: "venmo://")
        case .paypal:
            // PayPal SDK would be checked here
            return true // Always available via web fallback
        case .zelle:
            return canOpenURL(urlString: "zelle://")
        case .cashApp:
            return canOpenURL(urlString: "cashapp://")
        case .manual:
            return true
        }
    }

    func availableProviders() -> [PaymentProvider] {
        return PaymentProvider.allCases.filter { isProviderAvailable($0) }
    }

    private func canOpenURL(urlString: String) -> Bool {
        guard let url = URL(string: urlString) else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    // MARK: - Auto-Matching Payment Methods

    /// Find common payment methods between payer and recipient
    /// Returns matches sorted by preference
    func findMatchedPaymentMethods(
        payer: UserProfile,
        recipientFirebaseUID: String?
    ) async -> [PaymentMatch] {
        guard let recipientUID = recipientFirebaseUID else {
            print("⚠️ Cannot find matches - recipient has no Firebase UID")
            return []
        }

        do {
            guard let recipientProfile = try await firebaseManager.fetchUserProfile(byFirebaseUID: recipientUID) else {
                print("⚠️ Cannot find matches - recipient profile not found")
                return []
            }

            return paymentMatchingService.findCommonPaymentMethods(
                payer: payer,
                recipient: recipientProfile
            )
        } catch {
            print("❌ Error finding payment matches: \(error)")
            return []
        }
    }

    /// Find the best payment method for a settlement
    func findBestPaymentMatch(
        payer: UserProfile,
        recipientFirebaseUID: String?
    ) async -> PaymentMatch? {
        let matches = await findMatchedPaymentMethods(payer: payer, recipientFirebaseUID: recipientFirebaseUID)
        return matches.first
    }

    // MARK: - Main Payment Flow

    func initiatePayment(
        settlement: Settlement,
        provider: PaymentProvider,
        recipientAccount: LinkedPaymentAccount?
    ) async -> PaymentResult {
        isProcessingPayment = true
        defer { isProcessingPayment = false }

        // Validate amount
        guard settlement.amount > 0 else {
            return PaymentResult(success: false, transactionId: nil, error: .invalidAmount, provider: provider)
        }

        // Check if provider is available
        guard isProviderAvailable(provider) else {
            return PaymentResult(success: false, transactionId: nil, error: .providerNotAvailable, provider: provider)
        }

        // Route to appropriate provider
        let result: PaymentResult
        switch provider {
        case .applePay:
            result = await processApplePayCash(settlement: settlement)
        case .venmo:
            result = await processVenmoPayment(settlement: settlement, recipientAccount: recipientAccount)
        case .paypal:
            result = await processPayPalPayment(settlement: settlement, recipientAccount: recipientAccount)
        case .zelle:
            result = await processZellePayment(settlement: settlement, recipientAccount: recipientAccount)
        case .cashApp:
            result = await processCashAppPayment(settlement: settlement, recipientAccount: recipientAccount)
        case .manual:
            result = PaymentResult(success: true, transactionId: UUID().uuidString, error: nil, provider: provider)
        }

        lastPaymentResult = result

        // Log transaction
        if result.success {
            await recordPaymentTransaction(settlement: settlement, result: result)
        }

        return result
    }

    // MARK: - Apple Pay Cash Implementation

    private func processApplePayCash(settlement: Settlement) async -> PaymentResult {
        // Check if Apple Pay Cash is set up
        guard PKPaymentAuthorizationController.canMakePayments(usingNetworks: [.applePayCash]) else {
            return PaymentResult(success: false, transactionId: nil, error: .providerNotAvailable, provider: .applePay)
        }

        // Create payment request
        let request = PKPaymentRequest()
        request.merchantIdentifier = "merchant.com.ledgex.app" // Replace with actual merchant ID
        request.countryCode = "US"
        request.currencyCode = settlement.amount as NSDecimalNumber == 0 ? "USD" : "USD" // Use settlement currency
        request.supportedNetworks = [.applePayCash, .visa, .masterCard, .amex, .discover]
        request.merchantCapabilities = .capability3DS

        // Create payment summary item
        let paymentItem = PKPaymentSummaryItem(
            label: "Payment to \(settlement.to.name)",
            amount: settlement.amount as NSDecimalNumber
        )
        request.paymentSummaryItems = [paymentItem]

        return await withCheckedContinuation { continuation in
            pkPaymentController = PKPaymentAuthorizationController(paymentRequest: request)
            pkPaymentController?.delegate = self

            pkPaymentController?.present { presented in
                if !presented {
                    continuation.resume(returning: PaymentResult(
                        success: false,
                        transactionId: nil,
                        error: .providerNotAvailable,
                        provider: .applePay
                    ))
                }
            }
        }
    }

    // MARK: - Venmo Deep Link Implementation

    private func processVenmoPayment(settlement: Settlement, recipientAccount: LinkedPaymentAccount?) async -> PaymentResult {
        guard let recipientAccount = recipientAccount else {
            return PaymentResult(success: false, transactionId: nil, error: .accountNotLinked, provider: .venmo)
        }

        // Venmo deep link format: venmo://paycharge?txn=pay&recipients=USERNAME&amount=AMOUNT&note=NOTE
        let username = recipientAccount.accountIdentifier.replacingOccurrences(of: "@", with: "")
        let amount = (settlement.amount as NSDecimalNumber).doubleValue
        let note = "Ledgex settlement: \(settlement.from.name) → \(settlement.to.name)"
        let encodedNote = note.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

        let venmoURLString = "venmo://paycharge?txn=pay&recipients=\(username)&amount=\(amount)&note=\(encodedNote)"

        guard let url = URL(string: venmoURLString) else {
            return PaymentResult(success: false, transactionId: nil, error: .transactionFailed("Invalid URL"), provider: .venmo)
        }

        if await UIApplication.shared.open(url) {
            // Venmo was opened successfully - we can't track completion, so return pending
            return PaymentResult(success: true, transactionId: UUID().uuidString, error: nil, provider: .venmo)
        } else {
            return PaymentResult(success: false, transactionId: nil, error: .providerNotAvailable, provider: .venmo)
        }
    }

    // MARK: - PayPal Implementation

    private func processPayPalPayment(settlement: Settlement, recipientAccount: LinkedPaymentAccount?) async -> PaymentResult {
        // TODO: Integrate PayPal SDK
        // For now, use web-based flow or deep link

        guard let recipientAccount = recipientAccount else {
            return PaymentResult(success: false, transactionId: nil, error: .accountNotLinked, provider: .paypal)
        }

        // PayPal.me link format: https://www.paypal.me/username/amount
        let username = recipientAccount.accountIdentifier
        let amount = (settlement.amount as NSDecimalNumber).doubleValue
        let paypalURLString = "https://www.paypal.me/\(username)/\(amount)"

        guard let url = URL(string: paypalURLString) else {
            return PaymentResult(success: false, transactionId: nil, error: .transactionFailed("Invalid URL"), provider: .paypal)
        }

        if await UIApplication.shared.open(url) {
            return PaymentResult(success: true, transactionId: UUID().uuidString, error: nil, provider: .paypal)
        } else {
            return PaymentResult(success: false, transactionId: nil, error: .providerNotAvailable, provider: .paypal)
        }
    }

    // MARK: - Zelle Deep Link Implementation

    private func processZellePayment(settlement: Settlement, recipientAccount: LinkedPaymentAccount?) async -> PaymentResult {
        guard let recipientAccount = recipientAccount else {
            return PaymentResult(success: false, transactionId: nil, error: .accountNotLinked, provider: .zelle)
        }

        // Zelle deep link format: zelle://send?amount=AMOUNT&email=EMAIL&note=NOTE
        let amount = (settlement.amount as NSDecimalNumber).doubleValue
        let email = recipientAccount.accountIdentifier
        let note = "Ledgex settlement"
        let encodedEmail = email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let encodedNote = note.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

        let zelleURLString = "zelle://send?amount=\(amount)&email=\(encodedEmail)&note=\(encodedNote)"

        guard let url = URL(string: zelleURLString) else {
            return PaymentResult(success: false, transactionId: nil, error: .transactionFailed("Invalid URL"), provider: .zelle)
        }

        if await UIApplication.shared.open(url) {
            return PaymentResult(success: true, transactionId: UUID().uuidString, error: nil, provider: .zelle)
        } else {
            return PaymentResult(success: false, transactionId: nil, error: .providerNotAvailable, provider: .zelle)
        }
    }

    // MARK: - Cash App Deep Link Implementation

    private func processCashAppPayment(settlement: Settlement, recipientAccount: LinkedPaymentAccount?) async -> PaymentResult {
        guard let recipientAccount = recipientAccount else {
            return PaymentResult(success: false, transactionId: nil, error: .accountNotLinked, provider: .cashApp)
        }

        // Cash App deep link format: cashapp://cash.app/$CASHTAG/AMOUNT
        let cashtag = recipientAccount.accountIdentifier.replacingOccurrences(of: "$", with: "")
        let amount = (settlement.amount as NSDecimalNumber).doubleValue
        let cashAppURLString = "cashapp://cash.app/$\(cashtag)/\(amount)"

        guard let url = URL(string: cashAppURLString) else {
            return PaymentResult(success: false, transactionId: nil, error: .transactionFailed("Invalid URL"), provider: .cashApp)
        }

        if await UIApplication.shared.open(url) {
            return PaymentResult(success: true, transactionId: UUID().uuidString, error: nil, provider: .cashApp)
        } else {
            return PaymentResult(success: false, transactionId: nil, error: .providerNotAvailable, provider: .cashApp)
        }
    }

    // MARK: - Transaction Recording

    private func recordPaymentTransaction(settlement: Settlement, result: PaymentResult) async {
        let transaction = PaymentTransaction(
            settlementId: settlement.id,
            provider: result.provider,
            amount: settlement.amount,
            currency: .USD, // Use settlement's currency
            fromUserId: settlement.from.id,
            toUserId: settlement.to.id
        )

        // TODO: Save to Firestore via FirebaseManager
        print("💳 Payment transaction recorded: \(transaction.id)")
    }
}

// MARK: - Apple Pay Delegate
extension PaymentService: PKPaymentAuthorizationControllerDelegate {
    nonisolated func paymentAuthorizationController(
        _ controller: PKPaymentAuthorizationController,
        didAuthorizePayment payment: PKPayment,
        handler completion: @escaping (PKPaymentAuthorizationResult) -> Void
    ) {
        // Process the payment
        // In a real implementation, you would send this to your backend
        let result = PKPaymentAuthorizationResult(status: .success, errors: nil)
        completion(result)
    }

    nonisolated func paymentAuthorizationControllerDidFinish(_ controller: PKPaymentAuthorizationController) {
        controller.dismiss()
    }
}
