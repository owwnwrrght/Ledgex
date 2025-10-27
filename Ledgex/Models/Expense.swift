import Foundation

enum SplitType: String, CaseIterable, Codable {
    case equal = "Split Equally"
    case custom = "Custom Split"
    case itemized = "Itemized Split"
}

struct Expense: Identifiable, Codable {
    var id = UUID()
    var description: String
    var amount: Decimal // Always stored in trip's base currency (USD by default)
    var originalAmount: Decimal // Amount in original currency
    var originalCurrency: Currency // Currency user entered
    var baseCurrency: Currency = .USD // Trip's base currency
    var exchangeRate: Decimal = Decimal(1) // Rate used for conversion
    var paidBy: Person
    var splitType: SplitType = .equal
    var participants: [Person]
    var customSplits: [UUID: Decimal] = [:] // PersonID: Amount (in base currency)
    var date: Date = Date()
    var category: ExpenseCategory = .other
    
    // New: Receipt photo support
    var receiptImageIds: [String] = [] // Firebase Storage URLs or local identifiers
    var hasReceipt: Bool { !receiptImageIds.isEmpty }
    
    var createdByUserId: UUID?
    
    // Firebase properties (not stored in local cache)
    enum CodingKeys: String, CodingKey {
        case id, description, amount, originalAmount, originalCurrency, baseCurrency, exchangeRate, paidBy, splitType, participants, customSplits, date, category, receiptImageIds, createdByUserId
    }
    
    // Helper to display original amount with currency
    var originalAmountFormatted: String {
        return CurrencyAmount(amount: originalAmount, currency: originalCurrency).formatted()
    }
    
    // Helper to show conversion info
    var conversionInfo: String? {
        if originalCurrency == baseCurrency {
            return nil
        }
        let baseAmount = CurrencyAmount(amount: amount, currency: baseCurrency).formatted()
        return "\(originalAmountFormatted) → \(baseAmount)"
    }
    
    // Helper initializer for creating expenses with currency conversion
    init(description: String, originalAmount: Decimal, originalCurrency: Currency, baseCurrency: Currency, exchangeRate: Decimal, paidBy: Person, participants: [Person], category: ExpenseCategory = .other) {
        self.id = UUID()
        self.description = description
        self.originalAmount = originalAmount
        self.originalCurrency = originalCurrency
        self.baseCurrency = baseCurrency
        self.exchangeRate = exchangeRate
        self.amount = originalAmount * exchangeRate
        self.paidBy = paidBy
        self.participants = participants
        self.category = category
    }
}
