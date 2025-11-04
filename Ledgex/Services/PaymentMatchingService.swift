import Foundation

// MARK: - Payment Match Result
struct PaymentMatch: Identifiable, Equatable {
    let id = UUID()
    let provider: PaymentProvider
    let payerAccount: LinkedPaymentAccount
    let recipientAccount: LinkedPaymentAccount
    let matchScore: Int // Higher is better - based on preference order

    var isPreferredByBoth: Bool {
        return (payerAccount.preferenceOrder ?? 99) <= 3 &&
               (recipientAccount.preferenceOrder ?? 99) <= 3
    }

    static func == (lhs: PaymentMatch, rhs: PaymentMatch) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - Payment Matching Service
class PaymentMatchingService {
    static let shared = PaymentMatchingService()

    private init() {}

    /// Find common payment methods between two users
    /// Returns matches sorted by preference (best match first)
    func findCommonPaymentMethods(
        payer: UserProfile,
        recipient: UserProfile
    ) -> [PaymentMatch] {
        var matches: [PaymentMatch] = []

        // Get verified accounts for both users
        let payerAccounts = payer.linkedPaymentAccounts.filter { $0.isVerified }
        let recipientAccounts = recipient.linkedPaymentAccounts.filter { $0.isVerified }

        // Find common providers
        for payerAccount in payerAccounts {
            if let recipientAccount = recipientAccounts.first(where: { $0.provider == payerAccount.provider }) {
                // Calculate match score based on preference orders
                let matchScore = calculateMatchScore(
                    payerPreference: payerAccount.preferenceOrder,
                    recipientPreference: recipientAccount.preferenceOrder
                )

                let match = PaymentMatch(
                    provider: payerAccount.provider,
                    payerAccount: payerAccount,
                    recipientAccount: recipientAccount,
                    matchScore: matchScore
                )

                matches.append(match)
            }
        }

        // Sort by match score (higher is better)
        return matches.sorted { $0.matchScore > $1.matchScore }
    }

    /// Find the best payment method between two users
    func findBestPaymentMethod(
        payer: UserProfile,
        recipient: UserProfile
    ) -> PaymentMatch? {
        return findCommonPaymentMethods(payer: payer, recipient: recipient).first
    }

    /// Check if two users have any common payment methods
    func hasCommonPaymentMethod(
        payer: UserProfile,
        recipient: UserProfile
    ) -> Bool {
        let payerProviders = Set(payer.linkedPaymentAccounts.filter { $0.isVerified }.map { $0.provider })
        let recipientProviders = Set(recipient.linkedPaymentAccounts.filter { $0.isVerified }.map { $0.provider })

        return !payerProviders.intersection(recipientProviders).isEmpty
    }

    /// Get all available payment methods for a user
    func getAvailablePaymentMethods(for user: UserProfile) -> [LinkedPaymentAccount] {
        return user.linkedPaymentAccounts
            .filter { $0.isVerified }
            .sorted { (a, b) -> Bool in
                let orderA = a.preferenceOrder ?? 999
                let orderB = b.preferenceOrder ?? 999
                return orderA < orderB
            }
    }

    /// Calculate a match score based on both users' preference orders
    /// Lower preference numbers are better (1 is best), so we invert the score
    private func calculateMatchScore(
        payerPreference: Int?,
        recipientPreference: Int?
    ) -> Int {
        let payerOrder = payerPreference ?? 100
        let recipientOrder = recipientPreference ?? 100

        // Lower preference numbers get higher scores
        // If both prefer (order <= 3), boost the score significantly
        let baseScore = (200 - payerOrder) + (200 - recipientOrder)

        // Bonus points if both have it in their top 3
        let bothPreferBonus = (payerOrder <= 3 && recipientOrder <= 3) ? 500 : 0

        // Extra bonus if it's #1 for both
        let topChoiceBonus = (payerOrder == 1 && recipientOrder == 1) ? 1000 : 0

        return baseScore + bothPreferBonus + topChoiceBonus
    }

    /// Get a human-readable description of the match quality
    func getMatchDescription(for match: PaymentMatch) -> String {
        let payerOrder = match.payerAccount.preferenceOrder ?? 99
        let recipientOrder = match.recipientAccount.preferenceOrder ?? 99

        if payerOrder == 1 && recipientOrder == 1 {
            return "Top choice for both users"
        } else if payerOrder <= 3 && recipientOrder <= 3 {
            return "Preferred by both users"
        } else if payerOrder <= 5 || recipientOrder <= 5 {
            return "Available option"
        } else {
            return "Common method"
        }
    }
}
