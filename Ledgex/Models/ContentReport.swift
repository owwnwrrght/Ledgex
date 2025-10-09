import Foundation

enum ReportedContentType: String, Codable {
    case tripName
    case expenseName
}

enum ReportReason: String, CaseIterable, Codable, Identifiable {
    case inappropriate
    case spam
    case incorrect
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inappropriate:
            return "Inappropriate or offensive"
        case .spam:
            return "Spam or scam"
        case .incorrect:
            return "Misleading or incorrect info"
        case .other:
            return "Something else"
        }
    }

    var requiresDetails: Bool {
        self == .other
    }
}

enum ReportStatus: String, Codable {
    case open
    case reviewing
    case resolved
    case dismissed
}

struct ContentReport: Identifiable, Codable {
    var id = UUID()
    var tripId: UUID
    var tripCode: String
    var tripName: String
    var contentType: ReportedContentType
    var contentText: String
    var expenseId: UUID?
    var expenseDescription: String?
    var reporterProfileId: UUID?
    var reporterFirebaseUID: String?
    var reporterName: String?
    var reason: ReportReason
    var additionalDetails: String?
    var status: ReportStatus = .open
    var platform: String = "iOS"
    var appVersion: String?
    var createdAt = Date()
}

struct ReportTarget: Identifiable, Equatable {
    let id = UUID()
    let tripId: UUID
    let tripCode: String
    let tripName: String
    let contentType: ReportedContentType
    let contentText: String
    let expenseId: UUID?
    let expenseDescription: String?

    init(trip: Trip, contentType: ReportedContentType, contentText: String, expense: Expense? = nil) {
        self.tripId = trip.id
        self.tripCode = trip.code
        self.tripName = trip.name
        self.contentType = contentType
        self.contentText = contentText.trimmingCharacters(in: .whitespacesAndNewlines)
        self.expenseId = expense?.id
        self.expenseDescription = expense.map { $0.description.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
}
