import Foundation

enum ExpenseCategory: String, CaseIterable, Codable, Identifiable {
    case accommodation = "Accommodation"
    case food = "Food & Dining"
    case transport = "Transport"
    case entertainment = "Entertainment"
    case shopping = "Shopping"
    case other = "Other"

    var id: String { rawValue }

    /// SF Symbol representing this category
    var icon: String {
        switch self {
        case .accommodation: return "bed.double"
        case .food: return "fork.knife"
        case .transport: return "car"
        case .entertainment: return "film"
        case .shopping: return "bag"
        case .other: return "tag"
        }
    }
}
