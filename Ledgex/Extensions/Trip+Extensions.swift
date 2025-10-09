import Foundation

extension Trip {
    // Helper computed properties instead of custom initializer
    var totalAmount: Decimal {
        expenses.reduce(Decimal.zero) { $0 + $1.amount }
    }
    
    var participantCount: Int {
        people.count
    }
    
    var expenseCount: Int {
        expenses.count
    }
}