import SwiftUI

struct EditExpenseView: View {
    @ObservedObject var viewModel: ExpenseViewModel
    @Environment(\.dismiss) var dismiss
    
    let expense: Expense
    
    @State private var description: String
    @State private var amount: String
    @State private var selectedCurrency: Currency
    @State private var selectedPayer: Person?
    @State private var splitType: SplitType
    @State private var selectedParticipants: Set<UUID>
    @State private var customAmounts: [UUID: String]
    @State private var showingCurrencyPicker = false
    @State private var isConverting = false
    @State private var currentExchangeRate: Decimal
    @State private var isLoadingRate = false
    
    // Receipt photo support
    @State private var receiptImages: [UIImage] = []
    @State private var existingReceiptIds: [String]
    
    @ObservedObject private var currencyService = CurrencyExchangeService.shared
    @ObservedObject private var profileManager = ProfileManager.shared
    
    init(expense: Expense, viewModel: ExpenseViewModel) {
        self.expense = expense
        self.viewModel = viewModel
        
        // Initialize state variables
        _description = State(initialValue: expense.description)
        _amount = State(initialValue: expense.originalAmount.description)
        _selectedCurrency = State(initialValue: expense.originalCurrency)
        _selectedPayer = State(initialValue: expense.paidBy)
        _splitType = State(initialValue: expense.splitType)
        _selectedParticipants = State(initialValue: Set(expense.participants.map { $0.id }))
        _currentExchangeRate = State(initialValue: expense.exchangeRate)
        _existingReceiptIds = State(initialValue: expense.receiptImageIds)
        
        // Initialize custom amounts
        var initialCustomAmounts: [UUID: String] = [:]
        if expense.splitType == .custom {
            for (personId, amount) in expense.customSplits {
                initialCustomAmounts[personId] = amount.description
            }
        }
        _customAmounts = State(initialValue: initialCustomAmounts)
    }
    
    var isValid: Bool {
        guard !description.isEmpty,
              let amountValue = Decimal(string: amount),
              amountValue > 0,
              selectedPayer != nil,
              !selectedParticipants.isEmpty else {
            return false
        }
        
        if splitType == .custom {
            let amounts = customAmounts.compactMap { Decimal(string: $0.value) }
            guard amounts.allSatisfy({ $0 >= 0 }) else { return false }
            let total = amounts.reduce(0, +)
            let difference = abs(NSDecimalNumber(decimal: total - amountValue * currentExchangeRate).doubleValue)
            return difference < 0.01
        }
        
        return true
    }
    
    var hasChanges: Bool {
        // Check if any values have changed from the original expense
        if description != expense.description ||
           Decimal(string: amount) != expense.originalAmount ||
           selectedCurrency != expense.originalCurrency ||
           selectedPayer?.id != expense.paidBy.id ||
           splitType != expense.splitType ||
           Set(expense.participants.map { $0.id }) != selectedParticipants ||
           receiptImages.count > 0 {
            return true
        }
        
        // Check custom splits
        if splitType == .custom {
            for (personId, amount) in expense.customSplits {
                if customAmounts[personId] != amount.description {
                    return true
                }
            }
        }
        
        return false
    }
    
    var remainingAmount: Decimal {
        guard let totalAmount = Decimal(string: amount) else { return 0 }
        let convertedAmount = totalAmount * currentExchangeRate
        let amounts = customAmounts.compactMap { Decimal(string: $0.value) }
        let allocated = amounts.reduce(0, +)
        return convertedAmount - allocated
    }
    
    var body: some View {
        NavigationView {
            Form {
                expenseDetailsSection
                splitTypeSection
                participantsSection
                
                if splitType == .custom && !amount.isEmpty {
                    remainingAmountSection
                }
                
                // Receipt attachment section
                ReceiptAttachmentView(receiptImages: $receiptImages)
                
                if !existingReceiptIds.isEmpty {
                    existingReceiptsSection
                }
            }
            .navigationTitle("Edit Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { updateExpense() }) {
                        HStack {
                            if isConverting || viewModel.isUploadingReceipts {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text(viewModel.isUploadingReceipts ? "Uploading..." : "Converting...")
                            } else {
                                Text("Save")
                            }
                        }
                    }
                    .disabled(!isValid || !hasChanges || isConverting || viewModel.isUploadingReceipts)
                }
            }
            .sheet(isPresented: $showingCurrencyPicker) {
                CurrencyPickerView(selectedCurrency: $selectedCurrency)
            }
            .onAppear {
                updateExchangeRate()
            }
            .onChange(of: selectedCurrency) { _ in
                updateExchangeRate()
            }
        }
    }
    
    @ViewBuilder
    private var expenseDetailsSection: some View {
        Section(header: Text("Expense Details")) {
            TextField("Description", text: $description)
            HStack {
                TextField("Amount", text: $amount)
                    .keyboardType(.decimalPad)
                Button(action: { showingCurrencyPicker = true }) {
                    Text(selectedCurrency.displayName)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                }
            }
            if selectedCurrency != viewModel.trip.baseCurrency && !amount.isEmpty {
                if let amountValue = Decimal(string: amount) {
                    HStack {
                        if isLoadingRate {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("Converting...")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                        } else {
                            Text("≈ \(CurrencyAmount(amount: amountValue * currentExchangeRate, currency: viewModel.trip.baseCurrency).formatted())")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                        Spacer()
                    }
                }
            }
            
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: "person.circle")
                    .foregroundColor(.secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Paid by")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(selectedPayer?.name ?? "Unknown")
                        .font(.body)
                        .fontWeight(.semibold)
                }

                Spacer()
            }

        }
    }
    
    @ViewBuilder
    private var splitTypeSection: some View {
        Section(header: Text("Split Type")) {
            Picker("How to split", selection: $splitType) {
                ForEach(SplitType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
        }
    }
    
    @ViewBuilder
    private var participantsSection: some View {
        Section(header: Text("Participants")) {
            ForEach(viewModel.people) { person in
                participantRow(for: person)
            }
        }
    }
    
    @ViewBuilder
    private func participantRow(for person: Person) -> some View {
        HStack {
            Button(action: {
                if selectedParticipants.contains(person.id) {
                    selectedParticipants.remove(person.id)
                    customAmounts.removeValue(forKey: person.id)
                } else {
                    selectedParticipants.insert(person.id)
                    if splitType == .custom {
                        customAmounts[person.id] = ""
                    }
                }
            }) {
                HStack {
                    Image(systemName: selectedParticipants.contains(person.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(selectedParticipants.contains(person.id) ? .blue : .gray)
                    Text(person.name)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    if splitType == .custom && selectedParticipants.contains(person.id) {
                        TextField("Amount", text: Binding(
                            get: { customAmounts[person.id] ?? "" },
                            set: { customAmounts[person.id] = $0 }
                        ))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        Text(viewModel.trip.baseCurrency.symbol)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var remainingAmountSection: some View {
        Section {
            HStack {
                Text("Remaining to allocate")
                Spacer()
                Text(CurrencyAmount(amount: remainingAmount, currency: viewModel.trip.baseCurrency).formatted())
                    .foregroundColor(abs(NSDecimalNumber(decimal: remainingAmount).doubleValue) < 0.01 ? .green : .red)
            }
        }
    }
    
    @ViewBuilder
    private var existingReceiptsSection: some View {
        Section(header: Text("Existing Receipts")) {
            Text("\(existingReceiptIds.count) receipt(s) attached")
                .foregroundColor(.secondary)
                .font(.caption)
        }
    }
    
    private func updateExchangeRate() {
        guard selectedCurrency != viewModel.trip.baseCurrency else {
            currentExchangeRate = Decimal(1)
            return
        }
        
        isLoadingRate = true
        Task {
            currentExchangeRate = await currencyService.getExchangeRate(from: selectedCurrency, to: viewModel.trip.baseCurrency)
            isLoadingRate = false
        }
    }
    
    private func updateExpense() {
        guard let amountValue = Decimal(string: amount),
              let payer = selectedPayer else { return }
        
        isConverting = true
        
        Task {
            print("💰 Updating expense: \(description)")
            
            // Create updated expense
            var updatedExpense = expense
            updatedExpense.description = description
            updatedExpense.originalAmount = amountValue
            updatedExpense.originalCurrency = selectedCurrency
            updatedExpense.exchangeRate = currentExchangeRate
            updatedExpense.amount = amountValue * currentExchangeRate
            updatedExpense.paidBy = payer
            updatedExpense.participants = viewModel.people.filter { selectedParticipants.contains($0.id) }
            updatedExpense.splitType = splitType
            
            if splitType == .custom {
                updatedExpense.customSplits = customAmounts.compactMapValues { Decimal(string: $0) }
            } else {
                updatedExpense.customSplits = [:]
            }
            
            // Upload new receipts if any exist
            if !receiptImages.isEmpty {
                print("📸 Uploading \(receiptImages.count) new receipt photos...")
                
                // Temporarily set the receipt images in the view model for upload
                viewModel.receiptImages = receiptImages
                
                let newUploadedUrls = await viewModel.uploadReceipts(for: updatedExpense)
                // Append new receipts to existing ones
                updatedExpense.receiptImageIds = existingReceiptIds + newUploadedUrls
                
                print("📎 Added \(newUploadedUrls.count) new receipt URLs to expense")
            }
            
            // Update the expense
            await MainActor.run {
                viewModel.updateExpense(updatedExpense)
                print("✅ Expense updated successfully")
            }
            
            await MainActor.run {
                dismiss()
            }
        }
    }
}
