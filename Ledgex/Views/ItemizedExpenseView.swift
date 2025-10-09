import SwiftUI

struct ItemizedExpenseView: View {
    @ObservedObject var viewModel: ExpenseViewModel
    @Environment(\.dismiss) var dismiss
    
    let receiptImage: UIImage
    let ocrResult: OCRResult
    
    @State private var description: String = ""
    @State private var selectedCurrency: Currency
    @State private var selectedPayer: Person?
    @State private var items: [ReceiptItem]
    @State private var showingCurrencyPicker = false
    @State private var isProcessing = false
    
    @ObservedObject private var profileManager = ProfileManager.shared
    
    init(viewModel: ExpenseViewModel, receiptImage: UIImage, ocrResult: OCRResult) {
        self.viewModel = viewModel
        self.receiptImage = receiptImage
        self.ocrResult = ocrResult
        
        // Initialize state with default values first
        let defaultCurrency = ProfileManager.shared.currentProfile?.preferredCurrency ?? viewModel.trip.baseCurrency
        _selectedCurrency = State(initialValue: defaultCurrency)
        _items = State(initialValue: ocrResult.items)
        _description = State(initialValue: ocrResult.merchantName ?? "Receipt from \(Date().formatted(date: .abbreviated, time: .omitted))")
    }
    
    var totalAmount: Decimal {
        items.reduce(Decimal.zero) { $0 + $1.totalPrice }
    }
    
    var grandTotal: Decimal {
        totalAmount + ocrResult.tax + ocrResult.tip
    }
    
    var isValid: Bool {
        let hasSelectedItems = items.contains { !$0.selectedBy.isEmpty }
        return hasSelectedItems && selectedPayer != nil && !description.isEmpty
    }
    
    var body: some View {
        NavigationView {
            Form {
                // Expense details
                Section("Expense Details") {
                    TextField("Description", text: $description)
                        .font(.body)
                    
                    Picker("Paid by", selection: $selectedPayer) {
                        Text("Choose who paid").tag(Optional<Person>.none)
                        ForEach(viewModel.people) { person in
                            Text(person.name).tag(Optional(person))
                        }
                    }
                    
                    HStack {
                        Text("Currency")
                        Spacer()
                        Button(action: { showingCurrencyPicker = true }) {
                            HStack(spacing: 4) {
                                Text(selectedCurrency.displayName)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption2)
                            }
                            .foregroundColor(.blue)
                        }
                    }
                }
                
                // Receipt items
                Section {
                    ForEach(items.indices, id: \.self) { index in
                        ItemRowView(
                            item: $items[index],
                            people: viewModel.people,
                            currency: selectedCurrency
                        )
                    }
                } header: {
                    Text("Items")
                } footer: {
                    Text("Tap each item to choose who ordered it.")
                        .font(.caption)
                }
                
                // Summary
                Section("Summary") {
                    VStack(spacing: 8) {
                        // Items subtotal
                        HStack {
                            Text("Subtotal")
                            Spacer()
                            Text(CurrencyAmount(amount: totalAmount, currency: selectedCurrency).formatted())
                        }
                        
                        // Tax (if any)
                        if ocrResult.tax > 0 {
                            HStack {
                                Text("Tax")
                                Spacer()
                                Text(CurrencyAmount(amount: ocrResult.tax, currency: selectedCurrency).formatted())
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        // Tip (if any)
                        if ocrResult.tip > 0 {
                            HStack {
                                Text("Tip")
                                Spacer()
                                Text(CurrencyAmount(amount: ocrResult.tip, currency: selectedCurrency).formatted())
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Divider()
                        
                        // Grand total
                        HStack {
                            Text("Total")
                                .font(.headline.weight(.semibold))
                            Spacer()
                            Text(CurrencyAmount(amount: grandTotal, currency: selectedCurrency).formatted())
                                .font(.headline.weight(.semibold))
                        }
                    }
                }
                
                // Per person breakdown
                let splits = calculateSplits()
                if !splits.isEmpty {
                    Section("Split Breakdown") {
                        ForEach(splits, id: \.person.id) { split in
                            HStack {
                                Text(split.person.name)
                                    .font(.body)
                                Spacer()
                                Text(CurrencyAmount(amount: split.amount, currency: selectedCurrency).formatted())
                                    .font(.body)
                                                                }
                        }
                        
                        if ocrResult.tax > 0 || ocrResult.tip > 0 {
                            Text("Tax and tip are split evenly among all participants.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Original receipt preview
                Section("Receipt") {
                    HStack {
                        Spacer()
                        Image(uiImage: receiptImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 200)
                            .cornerRadius(12)
                            .shadow(radius: 2)
                        Spacer()
                    }
                }
            }
            .navigationTitle("Split Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Add Expense") {
                        addItemizedExpense()
                    }
                    .disabled(!isValid || isProcessing)
                                    }
            }
            .sheet(isPresented: $showingCurrencyPicker) {
                CurrencyPickerView(selectedCurrency: $selectedCurrency)
            }
        }
    }
    
    private func calculateSplits() -> [(person: Person, amount: Decimal)] {
        var splits: [UUID: Decimal] = [:]
        
        // Calculate each person's share based on selected items
        for item in items {
            let pricePerPerson = item.pricePerPerson
            for personId in item.selectedBy {
                splits[personId, default: 0] += pricePerPerson
            }
        }
        
        // Get all people who ordered items
        let participatingPeople = viewModel.people.filter { person in
            items.contains { $0.selectedBy.contains(person.id) }
        }
        
        // Split tax and tip evenly among participating people
        if !participatingPeople.isEmpty {
            let taxAndTipPerPerson = (ocrResult.tax + ocrResult.tip) / Decimal(participatingPeople.count)
            for person in participatingPeople {
                splits[person.id, default: 0] += taxAndTipPerPerson
            }
        }
        
        // Convert to array
        return viewModel.people.compactMap { person in
            guard let amount = splits[person.id], amount > 0 else { return nil }
            return (person: person, amount: amount)
        }
    }
    
    private func addItemizedExpense() {
        guard let payer = selectedPayer else { return }
        
        isProcessing = true
        
        Task {
            // Calculate exchange rate if needed
            let exchangeRate: Decimal = if selectedCurrency != viewModel.trip.baseCurrency {
                await CurrencyExchangeService.shared.getExchangeRate(
                    from: selectedCurrency,
                    to: viewModel.trip.baseCurrency
                )
            } else {
                Decimal(1)
            }
            
            // Create expense with itemized split
            var expense = Expense(
                description: description,
                originalAmount: grandTotal,
                originalCurrency: selectedCurrency,
                baseCurrency: viewModel.trip.baseCurrency,
                exchangeRate: exchangeRate,
                paidBy: payer,
                participants: viewModel.people.filter { person in
                    items.contains { $0.selectedBy.contains(person.id) }
                }
            )
            
            expense.splitType = .itemized
            expense.receiptItems = items
            
            // Calculate custom splits based on items
            let splits = calculateSplits()
            expense.customSplits = Dictionary(uniqueKeysWithValues: splits.map { 
                ($0.person.id, $0.amount * exchangeRate)
            })
            
            // Upload receipt image
            viewModel.receiptImages = [receiptImage]
            let uploadedUrls = await viewModel.uploadReceipts(for: expense)
            expense.receiptImageIds = uploadedUrls
            
            // Add the expense
            await MainActor.run {
                viewModel.addExpense(expense)
                dismiss()
            }
        }
    }
}

// MARK: - Item Row View
struct ItemRowView: View {
    @Binding var item: ReceiptItem
    let people: [Person]
    let currency: Currency
    
    @State private var isExpanded = false
    
    private var selectedPeopleNames: String {
        let names = people
            .filter { item.selectedBy.contains($0.id) }
            .map { $0.name }
        
        if names.isEmpty {
            return "No one selected"
        } else if names.count == 1 {
            return names[0]
        } else {
            return "\(names.count) people"
        }
    }
    
    private var hasSelection: Bool {
        !item.selectedBy.isEmpty
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main item row
            Button(action: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isExpanded.toggle()
                }
            }) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name)
                            .font(.body.weight(.medium))
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                        
                        HStack(spacing: 8) {
                            if item.quantity > 1 {
                                Text("\(item.quantity)x")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Text(formatPrice(item.price))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(formatPrice(item.totalPrice))
                            .font(.body.weight(.semibold))
                            .foregroundColor(.primary)
                        
                        HStack(spacing: 4) {
                            if hasSelection {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            } else {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                            
                            Text(selectedPeopleNames)
                                .font(.caption)
                                .foregroundColor(hasSelection ? .green : .orange)
                        }
                    }
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .animation(.easeInOut(duration: 0.3), value: isExpanded)
                }
                .padding(.vertical, 8)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Expanded people selection
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    Divider()
                        .padding(.top, 8)
                    
                    Text("Who ordered this item?")
                        .font(.subheadline)
                                                .foregroundColor(.primary)
                    
                    VStack(spacing: 8) {
                        ForEach(people) { person in
                            Button(action: {
                                togglePerson(person)
                            }) {
                                HStack(spacing: 12) {
                                    Image(systemName: item.selectedBy.contains(person.id) ? "checkmark.circle.fill" : "circle")
                                        .font(.title3)
                                        .foregroundColor(item.selectedBy.contains(person.id) ? .blue : Color(.systemGray3))
                                    
                                    Text(person.name)
                                        .font(.body)
                                        .foregroundColor(.primary)
                                    
                                    Spacer()
                                    
                                    if item.selectedBy.contains(person.id) && !item.selectedBy.isEmpty {
                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text(formatPrice(item.pricePerPerson))
                                                .font(.subheadline)
                                                                                                .foregroundColor(.primary)
                                            Text("per person")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func togglePerson(_ person: Person) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if item.selectedBy.contains(person.id) {
                item.selectedBy.remove(person.id)
            } else {
                item.selectedBy.insert(person.id)
            }
        }
    }
    
    private func formatPrice(_ price: Decimal) -> String {
        return CurrencyAmount(amount: price, currency: currency).formatted()
    }
}