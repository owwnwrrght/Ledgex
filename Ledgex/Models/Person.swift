import Foundation

struct Person: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var totalPaid: Decimal = .zero
    var totalOwed: Decimal = .zero
    var isManuallyAdded: Bool = false  // True for people without the app
    var hasCompletedExpenses: Bool = false
    
    // Firebase properties (not stored in local cache)
    enum CodingKeys: String, CodingKey {
        case id, name, totalPaid, totalOwed, isManuallyAdded, hasCompletedExpenses
    }
}
