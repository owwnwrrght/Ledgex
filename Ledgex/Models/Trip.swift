import Foundation

enum TripPhase: String, Codable {
    case setup      // Adding people, no expenses yet
    case active     // Expenses can be added
    case completed  // All settled up
}

struct Trip: Identifiable, Codable {
    var id = UUID()
    var name: String
    var code: String
    var people: [Person] = []
    var expenses: [Expense] = []
    var createdDate = Date()
    var lastModified = Date()
    var baseCurrency: Currency = .USD
    var version: Int = 1 // For future migration support
    var flagEmoji: String = Trip.defaultFlag
    var phase: TripPhase = .setup

    // New: Notification settings
    var notificationsEnabled: Bool = true
    var lastNotificationCheck: Date? = nil
    var settlementReceipts: [SettlementReceipt] = []

    enum CodingKeys: String, CodingKey {
        case id, name, code, people, expenses, createdDate, lastModified, baseCurrency, version, flagEmoji, phase, notificationsEnabled, lastNotificationCheck, settlementReceipts
    }
    
    var totalExpenses: Decimal {
        expenses.reduce(Decimal.zero) { $0 + $1.amount }
    }
    
    static func generateTripCode() -> String {
        let charset = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        let randomCount = 8
        let randomPart = String((0..<randomCount).compactMap { _ in charset.randomElement() })
        let timestampSuffix = String(format: "%02d", Int(Date().timeIntervalSince1970) % 100)
        return randomPart + timestampSuffix
    }

    static let codeLength = 10
    static let defaultFlag = "✈️"
}
