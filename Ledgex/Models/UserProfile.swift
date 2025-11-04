import Foundation

struct UserProfile: Codable {
    var name: String
    var id: UUID = UUID()
    var firebaseUID: String? = nil  // Firebase Auth UID for cross-device linking
    var dateCreated: Date = Date()
    var preferredCurrency: Currency = .USD
    var tripCodes: [String] = []  // List of trip codes the user is part of
    var lastSynced: Date? = nil

    // Push notification token
    var pushToken: String? = nil
    var notificationsEnabled: Bool = true

    // Payment integrations
    var linkedPaymentAccounts: [LinkedPaymentAccount] = []
    var defaultPaymentProvider: PaymentProvider?

    init(name: String, firebaseUID: String? = nil) {
        self.name = name
        self.firebaseUID = firebaseUID
    }

    func paymentAccount(for provider: PaymentProvider) -> LinkedPaymentAccount? {
        return linkedPaymentAccounts.first(where: { $0.provider == provider && $0.isVerified })
    }

    var hasLinkedPaymentAccounts: Bool {
        return !linkedPaymentAccounts.filter({ $0.isVerified }).isEmpty
    }
}