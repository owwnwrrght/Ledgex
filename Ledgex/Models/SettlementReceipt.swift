import Foundation

struct SettlementReceipt: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var fromPersonId: UUID
    var toPersonId: UUID
    var amount: Decimal
    var isReceived: Bool
    var updatedAt: Date
    
    init(id: UUID = UUID(), fromPersonId: UUID, toPersonId: UUID, amount: Decimal, isReceived: Bool = false, updatedAt: Date = Date()) {
        self.id = id
        self.fromPersonId = fromPersonId
        self.toPersonId = toPersonId
        self.amount = amount
        self.isReceived = isReceived
        self.updatedAt = updatedAt
    }
}
