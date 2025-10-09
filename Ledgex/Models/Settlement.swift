import Foundation

struct Settlement: Identifiable {
    let id = UUID()
    let from: Person
    let to: Person
    let amount: Decimal
    var isReceived: Bool = false
}
