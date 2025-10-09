import Foundation
import OSLog
import SwiftUI
import Combine

@MainActor
class ExpenseViewModel: ObservableObject {
    @Published var trip: Trip
    @Published var receiptImages: [UIImage] = []
    @Published var isUploadingReceipts = false
    @Published var pendingItemizedExpense: (UIImage, OCRResult)?
    
    var people: [Person] {
        trip.people
    }
    
    var expenses: [Expense] {
        trip.expenses
    }
    
    var settlements: [Settlement] {
        calculateSettlements()
    }
    
    var pendingConfirmations: [Person] {
        trip.people.filter { !$0.hasCompletedExpenses }
    }
    
    var allParticipantsConfirmed: Bool {
        !trip.people.isEmpty && pendingConfirmations.isEmpty
    }

    var confirmationProgress: Double {
        guard !trip.people.isEmpty else { return 0 }
        let confirmed = trip.people.count - pendingConfirmations.count
        return Double(confirmed) / Double(trip.people.count)
    }

    var canAddExpenses: Bool {
        trip.phase == .active && !trip.people.isEmpty
    }

    var isInSetupPhase: Bool {
        trip.phase == .setup
    }
    
    private let dataStore: TripDataStore
    weak var tripListViewModel: TripListViewModel?
    @Published var lastError: AppError?
    private let logger = Logger(subsystem: "com.OwenWright.Ledgex-ios", category: "ExpenseViewModel")
    
    init(trip: Trip, dataStore: TripDataStore? = nil, tripListViewModel: TripListViewModel? = nil) {
        self.trip = trip
        self.dataStore = dataStore ?? FirebaseManager.shared
        self.tripListViewModel = tripListViewModel
        
        // Setup Firebase listener for this trip
        if let firebaseManager = dataStore as? FirebaseManager {
            firebaseManager.setupTripListener(for: trip.code) { [weak self] updatedTrip in
                guard let self = self else { return }
                self.trip = updatedTrip
                self.recalculateBalances()
                self.saveChanges()
                self.tripListViewModel?.updateTrip(updatedTrip)
            }
        }
    }
    
    func refreshFromCloud() async {
        await tripListViewModel?.syncTrip(trip)
        if let updatedTrip = self.tripListViewModel?.trips.first(where: { $0.id == self.trip.id }) {
            self.trip = updatedTrip
            // Recalculate balances after syncing from Firebase
            self.recalculateBalances()
            self.saveChanges()
        }
    }

    func canToggleCompletion(for person: Person) -> Bool {
        if person.isManuallyAdded { return true }
        guard let profile = ProfileManager.shared.currentProfile else { return false }
        return profile.id == person.id
    }
    
    func isCurrentUser(person: Person) -> Bool {
        guard let profile = ProfileManager.shared.currentProfile else { return false }
        return profile.id == person.id
    }

    func toggleCompletion(for person: Person) async {
        guard let index = trip.people.firstIndex(where: { $0.id == person.id }) else { return }
        trip.people[index].hasCompletedExpenses.toggle()
        tripListViewModel?.updateTrip(trip)
        saveChanges()
        do {
            let savedTrip = try await dataStore.saveTrip(trip)
            self.trip = savedTrip
            tripListViewModel?.updateTrip(savedTrip)
            if allParticipantsConfirmed {
                NotificationService.shared.sendTripNotification(.readyToSettle(tripName: trip.name))
            }
        } catch {
            await handleError(error, fallback: "We couldn't update the completion status. Please try again.")
        }
    }
    
    func addPerson(name: String) {
        let person = Person(name: name)

        // Add locally first for immediate UI update
        trip.people.append(person)

        // If expenses already exist and we're in active phase, this is a problem - prevent it
        if !trip.expenses.isEmpty && trip.phase == .active {
            print("⚠️ Cannot add people after expenses have been added in active phase")
            trip.people.removeLast()
            return
        }

        resetConfirmationsIfNeeded()
        recalculateBalances()
        saveChanges()

        // Save entire trip to Firebase (including the new person)
        Task { [weak self] in
            guard let self else { return }
            do {
                let savedTrip = try await self.dataStore.saveTrip(self.trip)
                await MainActor.run {
                    self.trip = savedTrip
                    self.tripListViewModel?.updateTrip(savedTrip)
                }
            } catch {
                await self.handleError(error, fallback: "We couldn't add that person. Please try again.")
            }
        }
    }
    
    func addManualPerson(name: String) {
        var person = Person(name: name)
        person.isManuallyAdded = true

        // Add locally first for immediate UI update
        trip.people.append(person)

        // If expenses already exist and we're in active phase, this is a problem - prevent it
        if !trip.expenses.isEmpty && trip.phase == .active {
            print("⚠️ Cannot add people after expenses have been added in active phase")
            trip.people.removeLast()
            return
        }

        resetConfirmationsIfNeeded()
        recalculateBalances()
        saveChanges()

        // Save entire trip to Firebase (including the new person)
        Task { [weak self] in
            guard let self else { return }
            do {
                let savedTrip = try await self.dataStore.saveTrip(self.trip)
                await MainActor.run {
                    self.trip = savedTrip
                    self.tripListViewModel?.updateTrip(savedTrip)
                }
            } catch {
                await self.handleError(error, fallback: "We couldn't add that person. Please try again.")
            }
        }
    }
    
    func removePerson(at offsets: IndexSet) {
        // Get the IDs of people being removed before removing them
        let removedPersonIds = offsets.map { trip.people[$0].id }
        
        trip.people.remove(atOffsets: offsets)
        resetConfirmationsIfNeeded()
        
        // Remove person from all expenses
        for i in trip.expenses.indices {
            trip.expenses[i].participants.removeAll { person in
                removedPersonIds.contains(person.id)
            }
        }
        
        recalculateBalances()
        saveChanges()
        
        // Save entire trip to Firebase
        Task { [weak self] in
            guard let self else { return }
            do {
                let savedTrip = try await self.dataStore.saveTrip(self.trip)
                await MainActor.run {
                    self.trip = savedTrip
                    self.tripListViewModel?.updateTrip(savedTrip)
                }
            } catch {
                await self.handleError(error, fallback: "We couldn't remove that person. Please try again.")
            }
        }
    }
    
    func addExpense(_ expense: Expense) {
        // Add locally first for immediate UI update
        trip.expenses.append(expense)
        resetConfirmationsIfNeeded()
        recalculateBalances()
        saveChanges()
        
        // Then sync to Firebase by saving the entire trip
        Task { [weak self] in
            guard let self else { return }
            do {
                let savedTrip = try await self.dataStore.saveTrip(self.trip)
                await MainActor.run {
                    self.trip = savedTrip
                    self.tripListViewModel?.updateTrip(savedTrip)
                }
            } catch {
                await self.handleError(error, fallback: "We couldn't save the expense. Please try again.")
            }
        }
    }
    
    func removeExpense(at offsets: IndexSet) {
        trip.expenses.remove(atOffsets: offsets)
        resetConfirmationsIfNeeded()
        recalculateBalances()
        saveChanges()
        
        // Save entire trip to Firebase
        Task { [weak self] in
            guard let self else { return }
            do {
                let savedTrip = try await self.dataStore.saveTrip(self.trip)
                await MainActor.run {
                    self.trip = savedTrip
                    self.tripListViewModel?.updateTrip(savedTrip)
                }
            } catch {
                await self.handleError(error, fallback: "We couldn't delete the expense. Please try again.")
            }
        }
    }

    func updateExpense(_ updatedExpense: Expense) {
        // Find the index of the expense to update
        guard let index = trip.expenses.firstIndex(where: { $0.id == updatedExpense.id }) else {
            print("❌ Expense not found for update")
            return
        }
        
        // Update locally first for immediate UI update
        trip.expenses[index] = updatedExpense
        resetConfirmationsIfNeeded()
        recalculateBalances()
        saveChanges()
        
        // Then sync to Firebase by saving the entire trip
        Task { [weak self] in
            guard let self else { return }
            do {
                let savedTrip = try await self.dataStore.saveTrip(self.trip)
                await MainActor.run {
                    self.trip = savedTrip
                    self.tripListViewModel?.updateTrip(savedTrip)
                }
            } catch {
                await self.handleError(error, fallback: "We couldn't update the expense. Please try again.")
            }
        }
    }

    func updateGroupDetails(name: String, baseCurrency: Currency, flagEmoji: String) async -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return false }

        let previousTrip = trip
        var updatedTrip = trip
        let currencyChanged = updatedTrip.baseCurrency != baseCurrency

        updatedTrip.name = trimmedName
        updatedTrip.flagEmoji = flagEmoji
        updatedTrip.baseCurrency = baseCurrency

        if currencyChanged {
            await convertExpenses(in: &updatedTrip, to: baseCurrency)
        }

        trip = updatedTrip
        recalculateBalances()
        saveChanges()
        tripListViewModel?.updateTrip(updatedTrip)

        do {
            let savedTrip = try await dataStore.saveTrip(updatedTrip)
            trip = savedTrip
            recalculateBalances()
            saveChanges()
            tripListViewModel?.updateTrip(savedTrip)
            return true
        } catch {
            trip = previousTrip
            recalculateBalances()
            saveChanges()
            tripListViewModel?.updateTrip(previousTrip)
            await handleError(error, fallback: "We couldn't save your group changes. Please try again.")
            return false
        }
    }

    // MARK: - Receipt Photo Management
    
    /// Upload receipt images using the improved batch upload method
    func uploadReceipts(for expense: Expense) async -> [String] {
        guard !receiptImages.isEmpty else {
            print("📝 No receipt images to upload")
            return []
        }
        
        isUploadingReceipts = true
        defer { isUploadingReceipts = false }
        
        do {
            print("🚀 Starting batch upload of \(receiptImages.count) receipts for expense: \(expense.description)")
            let uploadedUrls = try await dataStore.uploadReceiptImages(receiptImages, for: expense.id.uuidString)
            print("🎉 Successfully uploaded \(uploadedUrls.count) receipt images")
            return uploadedUrls
        } catch {
            print("💥 Batch upload failed: \(error)")
            // Fallback to individual uploads
            return await uploadReceiptsIndividually(for: expense)
        }
    }
    
    /// Fallback method for individual uploads if batch fails
    private func uploadReceiptsIndividually(for expense: Expense) async -> [String] {
        print("🔄 Falling back to individual uploads...")
        var uploadedUrls: [String] = []
        
        for (index, image) in receiptImages.enumerated() {
            guard let imageData = image.jpegData(compressionQuality: 0.8) else {
                print("⚠️ Could not convert image \(index + 1) to JPEG")
                continue
            }
            
            do {
                let url = try await dataStore.uploadReceiptImage(imageData, for: expense.id.uuidString)
                uploadedUrls.append(url)
                print("✅ Individual upload \(index + 1)/\(receiptImages.count) successful")
            } catch {
                print("❌ Individual upload \(index + 1) failed: \(error)")
            }
        }
        
        return uploadedUrls
    }

    private func convertExpenses(in trip: inout Trip, to newBaseCurrency: Currency) async {
        let exchangeService = CurrencyExchangeService.shared

        for index in trip.expenses.indices {
            var expense = trip.expenses[index]
            let convertedAmount = await exchangeService.convert(amount: expense.originalAmount, from: expense.originalCurrency, to: newBaseCurrency)
            let previousAmount = expense.amount

            expense.amount = convertedAmount
            expense.baseCurrency = newBaseCurrency

            if expense.originalAmount != 0 {
                expense.exchangeRate = convertedAmount / expense.originalAmount
            } else {
                expense.exchangeRate = Decimal(1)
            }

            let factor: Decimal
            if previousAmount == 0 {
                factor = convertedAmount == 0 ? Decimal(0) : Decimal(1)
            } else {
                factor = convertedAmount == 0 ? Decimal(0) : (convertedAmount / previousAmount)
            }
            expense.customSplits = expense.customSplits.mapValues { $0 * factor }

            trip.expenses[index] = expense
        }
    }

    private func resetConfirmationsIfNeeded() {
        var changed = false
        for index in trip.people.indices {
            if trip.people[index].hasCompletedExpenses {
                trip.people[index].hasCompletedExpenses = false
                changed = true
            }
        }
        if changed {
            tripListViewModel?.updateTrip(trip)
        }
    }

    @MainActor
    func updateTripFlag(_ flag: String) async {
        guard trip.flagEmoji != flag else { return }
        trip.flagEmoji = flag
        tripListViewModel?.updateTrip(trip)
        saveChanges()
        do {
            let savedTrip = try await dataStore.saveTrip(trip)
            await MainActor.run {
                self.trip = savedTrip
                self.tripListViewModel?.updateTrip(savedTrip)
            }
        } catch {
            print("Failed to update trip flag: \(error)")
        }
    }

    @MainActor
    func startTrip() async {
        guard trip.phase == .setup else { return }
        guard !trip.people.isEmpty else { return }

        trip.phase = .active
        tripListViewModel?.updateTrip(trip)
        saveChanges()

        do {
            let savedTrip = try await dataStore.saveTrip(trip)
            await MainActor.run {
                self.trip = savedTrip
                self.tripListViewModel?.updateTrip(savedTrip)
            }
            print("✅ Group started - now in active phase")
        } catch {
            print("❌ Failed to start trip: \(error)")
        }
    }
    
    private func saveChanges() {
        // Only update lastModified for significant changes, not balance recalculations
        // tripListViewModel?.updateTrip(trip) - commented out to prevent spam
        // Just save locally for now
        DataManager.shared.saveTrips(tripListViewModel?.trips ?? [])
    }
    
    // Debug function to validate balance calculations
    private func validateBalances() -> String {
        let totalPaid = trip.people.reduce(Decimal.zero) { $0 + $1.totalPaid }
        let totalOwed = trip.people.reduce(Decimal.zero) { $0 + $1.totalOwed }
        let totalExpenses = trip.expenses.reduce(Decimal.zero) { $0 + $1.amount }
        
        var report = "Balance Validation Report:\n"
        report += "Total Expenses: $\(totalExpenses)\n"
        report += "Total Paid: $\(totalPaid)\n"
        report += "Total Owed: $\(totalOwed)\n"
        report += "Paid-Expense Diff: $\(totalPaid - totalExpenses)\n"
        report += "Owed-Expense Diff: $\(totalOwed - totalExpenses)\n"
        
        return report
    }
    
    private func recalculateBalances() {
        print("\n=== Recalculating Balances ===")
        
        // Reset everyone's balances
        for i in trip.people.indices {
            trip.people[i].totalPaid = .zero
            trip.people[i].totalOwed = .zero
        }
        
        // Calculate each expense
        for expense in trip.expenses {
            // Find the payer in the current people array
            guard let payerIndex = trip.people.firstIndex(where: { $0.id == expense.paidBy.id }) else {
                print("⚠️ Skipping expense '\(expense.description)' - payer not found")
                continue
            }
            
            // Add to payer's totalPaid
            trip.people[payerIndex].totalPaid += expense.amount
            
            // Calculate what each participant owes
            if expense.splitType == .equal && !expense.participants.isEmpty {
                let sharePerPerson = expense.amount / Decimal(expense.participants.count)
                
                for participant in expense.participants {
                    if let participantIndex = trip.people.firstIndex(where: { $0.id == participant.id }) {
                        trip.people[participantIndex].totalOwed += sharePerPerson
                    }
                }
            } else if expense.splitType == .custom || expense.splitType == .itemized {
                // For custom and itemized splits, use the amounts specified
                for (personId, amount) in expense.customSplits {
                    if let participantIndex = trip.people.firstIndex(where: { $0.id == personId }) {
                        trip.people[participantIndex].totalOwed += amount
                    }
                }
            }
        }
        
        print("=== Balance Calculation Complete ===\n")
    }
    
    private func calculateSettlements() -> [Settlement] {
        var rawSettlements: [(from: Person, to: Person, amount: Decimal)] = []
        
        // Calculate net balance for each person (positive = owed money, negative = owes money)
        var balances: [(person: Person, balance: Decimal)] = trip.people.map { person in
            let netBalance = person.totalPaid - person.totalOwed
            return (person, netBalance)
        }
        
        // Sort by balance (debtors first, then creditors)
        balances.sort { $0.balance < $1.balance }
        
        var debtorIndex = 0
        var creditorIndex = balances.count - 1
        
        while debtorIndex < creditorIndex {
            let debtor = balances[debtorIndex]
            let creditor = balances[creditorIndex]
            
            // Skip if no debt or credit
            if debtor.balance >= 0 || creditor.balance <= 0 {
                break
            }
            
            // Calculate settlement amount
            let settlementAmount = min(abs(debtor.balance), creditor.balance)
            
            if settlementAmount > 0.01 { // Only create settlements for amounts > 1 cent
                rawSettlements.append((from: debtor.person,
                                       to: creditor.person,
                                       amount: settlementAmount))
            }
            
            // Update balances
            balances[debtorIndex].balance += settlementAmount
            balances[creditorIndex].balance -= settlementAmount
            
            // Move indices if balance is settled
            if abs(balances[debtorIndex].balance) < 0.01 {
                debtorIndex += 1
            }
            if balances[creditorIndex].balance < 0.01 {
                creditorIndex -= 1
            }
        }

        let receipts = synchronizeSettlementReceipts(with: rawSettlements)
        let receiptsByKey = Dictionary(uniqueKeysWithValues: receipts.map { (SettlementKey(fromPersonId: $0.fromPersonId, toPersonId: $0.toPersonId), $0) })

        let settlements = rawSettlements.map { entry -> Settlement in
            let key = SettlementKey(fromPersonId: entry.from.id, toPersonId: entry.to.id)
            let receipt = receiptsByKey[key]
            return Settlement(from: entry.from,
                              to: entry.to,
                              amount: entry.amount,
                              isReceived: receipt?.isReceived ?? false)
        }

        return settlements
    }

    @MainActor
    func toggleSettlementReceived(_ settlement: Settlement) async {
        guard canToggleSettlementReceived(settlement) else { return }
        guard let index = trip.settlementReceipts.firstIndex(where: { $0.fromPersonId == settlement.from.id && $0.toPersonId == settlement.to.id }) else { return }

        trip.settlementReceipts[index].isReceived.toggle()
        trip.settlementReceipts[index].updatedAt = Date()

        tripListViewModel?.updateTrip(trip)
        saveChanges()

        do {
            let savedTrip = try await dataStore.saveTrip(trip)
            self.trip = savedTrip
            self.tripListViewModel?.updateTrip(savedTrip)
        } catch {
            print("Failed to update settlement receipt: \(error)")
        }
    }

    func canToggleSettlementReceived(_ settlement: Settlement) -> Bool {
        if settlement.to.isManuallyAdded {
            return true
        }
        return isCurrentUser(person: settlement.to)
    }

    private func synchronizeSettlementReceipts(with settlements: [(from: Person, to: Person, amount: Decimal)]) -> [SettlementReceipt] {
        var existing = Dictionary(uniqueKeysWithValues: trip.settlementReceipts.map { (SettlementKey(fromPersonId: $0.fromPersonId, toPersonId: $0.toPersonId), $0) })
        var updated: [SettlementReceipt] = []

        for entry in settlements {
            let key = SettlementKey(fromPersonId: entry.from.id, toPersonId: entry.to.id)

            if var receipt = existing.removeValue(forKey: key) {
                if !receipt.amount.isApproximatelyEqual(to: entry.amount) {
                    receipt.amount = entry.amount
                    if receipt.isReceived {
                        receipt.isReceived = false
                    }
                    receipt.updatedAt = Date()
                }
                updated.append(receipt)
            } else {
                let receipt = SettlementReceipt(fromPersonId: entry.from.id,
                                                 toPersonId: entry.to.id,
                                                 amount: entry.amount,
                                                 isReceived: false,
                                                 updatedAt: Date())
                updated.append(receipt)
            }
        }

        if trip.settlementReceipts != updated {
            trip.settlementReceipts = updated
        }

        return updated
    }
}

private extension ExpenseViewModel {
    func handleError(_ error: Error, fallback: String) async {
        logger.error("\(error.localizedDescription, privacy: .public)")
        await MainActor.run {
            lastError = AppError.make(from: error, fallbackMessage: fallback)
        }
    }
}

private struct SettlementKey: Hashable {
    let fromPersonId: UUID
    let toPersonId: UUID
}

private extension Decimal {
    func isApproximatelyEqual(to other: Decimal, tolerance: Decimal = 0.01) -> Bool {
        let difference = NSDecimalNumber(decimal: self - other).doubleValue
        return abs(difference) <= NSDecimalNumber(decimal: tolerance).doubleValue
    }
}
