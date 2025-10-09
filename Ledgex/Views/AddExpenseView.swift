import SwiftUI
import UIKit

enum ExpenseEntryMode: String, Identifiable {
    case manual
    case quick

    var id: String { rawValue }

    var navigationTitle: String {
        switch self {
        case .manual: return "Add Manually"
        case .quick: return "Quick Add"
        }
    }

    var headline: String {
        switch self {
        case .manual: return "Manual expense entry"
        case .quick: return "Fast expense entry"
        }
    }

    var message: String {
        switch self {
        case .manual:
            return "Customize the split, currencies, and attach receipts."
        case .quick:
            return "Perfect for simple splits. We’ll split equally unless you change it."
        }
    }
}

struct AddExpenseView: View {
    let mode: ExpenseEntryMode
    @ObservedObject var viewModel: ExpenseViewModel
    @Environment(\.dismiss) var dismiss
    
    @State private var description = ""
    @State private var amount = ""
    @State private var selectedCurrency: Currency = .USD
    @State private var splitType: SplitType = .equal
    @State private var selectedParticipants: Set<UUID> = []
    @State private var customAmounts: [UUID: String] = [:]
    @State private var showingCurrencyPicker = false
    @State private var isConverting = false
    @State private var currentExchangeRate: Decimal = Decimal(1)
    @State private var isLoadingRate = false

    // Receipt photo support
    @State private var receiptImages: [UIImage] = []
    @State private var showingReceiptScanner = false
    @State private var hasAppliedInitialDefaults = false
    @State private var lastExpenseTemplate: Expense?
    
    @ObservedObject private var currencyService = CurrencyExchangeService.shared
    @ObservedObject private var profileManager = ProfileManager.shared
    
    @FocusState private var focusedField: Field?
    
    private let quickAmountSuggestions: [Decimal] = [5, 10, 20, 50, 100]
    
    private enum Field { case description, amount }
    
    init(viewModel: ExpenseViewModel, mode: ExpenseEntryMode = .manual) {
        self.mode = mode
        self._viewModel = ObservedObject(initialValue: viewModel)
    }

    // MARK: - Validation
    var isValid: Bool {
        guard let amountValue = decimal(from: amount),
              amountValue > 0,
              currentUserPerson != nil,
              !selectedParticipants.isEmpty else {
            return false
        }

        if mode == .manual && description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }

        if splitType == .custom {
            let values = selectedParticipants.compactMap { id -> Decimal? in
                guard let text = customAmounts[id], !text.isEmpty else { return nil }
                return decimal(from: text)
            }
            guard values.count == selectedParticipants.count else { return false }
            guard values.allSatisfy({ $0 >= 0 }) else { return false }
            let total = values.reduce(0, +)
            let difference = abs(NSDecimalNumber(decimal: total - amountValue * currentExchangeRate).doubleValue)
            return difference < 0.01
        }
        
        return true
    }
    
    var remainingAmount: Decimal {
        guard let totalAmount = decimal(from: amount) else { return 0 }
        let convertedAmount = totalAmount * currentExchangeRate
        let allocated = selectedParticipants.reduce(Decimal.zero) { result, id in
            guard let text = customAmounts[id], let value = decimal(from: text) else { return result }
            return result + value
        }
        return convertedAmount - allocated
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(mode.headline)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text(mode.message)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                if mode == .manual, let template = lastExpenseTemplate {
                    templateSection(for: template)
                }
                
                expenseDetailsSection
                quickAmountSection
                splitTypeSection
                participantsSection
                
                if splitType == .custom && !amount.isEmpty {
                    remainingAmountSection
                }
                
                receiptSection
            }
            .navigationTitle(mode.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: joinExpenseFlow) {
                        if isConverting || viewModel.isUploadingReceipts {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text(viewModel.isUploadingReceipts ? "Saving…" : "Converting…")
                            }
                        } else {
                            Text("Add Expense")
                        }
                    }
                    .disabled(!isValid || isConverting || viewModel.isUploadingReceipts)
                }
            }
            .sheet(isPresented: $showingCurrencyPicker) {
                CurrencyPickerView(selectedCurrency: $selectedCurrency)
            }
            .fullScreenCover(isPresented: $showingReceiptScanner) {
                ReceiptScannerView(viewModel: viewModel) { image, ocrResult in
                    dismiss()
                    viewModel.pendingItemizedExpense = (image, ocrResult)
                }
            }
            .onAppear(perform: configureView)
            .onChange(of: selectedCurrency) { _ in updateExchangeRate() }
            .onChange(of: viewModel.people.map(\.id)) { _ in
                syncSelection(with: viewModel.people)
            }
            .onChange(of: splitType, perform: handleSplitTypeChange)
            .onChange(of: viewModel.expenses.map(\.id)) { _ in
                lastExpenseTemplate = viewModel.expenses.last
            }
        }
    }
    
    // MARK: - Sections
    @ViewBuilder
    private func templateSection(for template: Expense) -> some View {
        Section("Speed Up") {
            Button {
                applyTemplate(template)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .foregroundColor(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Reuse last expense")
                            .font(.body.weight(.semibold))
                        Text("Prefill from \(template.description)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var expenseDetailsSection: some View {
        Section {
            // Description
            HStack {
                Image(systemName: "text.alignleft")
                    .foregroundColor(.secondary)
                    .frame(width: 24)
                TextField("Expense description", text: $description)
                    .font(.body)
                    .focused($focusedField, equals: .description)
            }

            // Amount with currency
            HStack {
                Image(systemName: "dollarsign.circle")
                    .foregroundColor(.secondary)
                    .frame(width: 24)
                TextField("0.00", text: $amount)
                    .keyboardType(.decimalPad)
                    .font(.body)
                    .focused($focusedField, equals: .amount)

                Button(action: { showingCurrencyPicker = true }) {
                    Text(selectedCurrency.rawValue)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.blue)
                }
            }

            // Currency conversion preview (inline, subtle)
            if selectedCurrency != viewModel.trip.baseCurrency, let amountValue = decimal(from: amount), amountValue > 0 {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundColor(.secondary)
                        .frame(width: 24)
                        .font(.caption)
                    if isLoadingRate {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Converting…")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    } else {
                        Text("\(CurrencyAmount(amount: amountValue * currentExchangeRate, currency: viewModel.trip.baseCurrency).formatted())")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    }
                    Spacer()
                }
            }

            // Paid by (restricted to the current user)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: "person.circle")
                    .foregroundColor(.secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Paid by")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(payerDisplayName)
                        .font(.body)
                        .fontWeight(.semibold)
                }

                Spacer()

                if currentUserPerson == nil {
                    Text("Add yourself to People")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

        } header: {
            Text("Expense Details")
        }
    }

    @ViewBuilder
    private var splitTypeSection: some View {
        if mode == .manual {
            Section("How to Split") {
                Picker("Split method", selection: $splitType) {
                    ForEach(SplitType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)
            }
        } else {
            Section("Split Method") {
                Label("Split equally", systemImage: "person.3")
                    .foregroundColor(.secondary)
                Text("Switch to manual entry to customize splits.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private var participantsSection: some View {
        Section {
            // Quick actions
            HStack(spacing: 8) {
                Button(action: {
                    selectedParticipants = Set(viewModel.people.map(\.id))
                    if splitType == .custom {
                        for id in selectedParticipants where customAmounts[id] == nil {
                            customAmounts[id] = ""
                        }
                    }
                }) {
                    Label("All", systemImage: "person.3.fill")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .disabled(selectedParticipants.count == viewModel.people.count)

                Button(action: {
                    if let me = currentUserPerson {
                        selectedParticipants = [me.id]
                    }
                }) {
                    Label("Just Me", systemImage: "person.fill")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .disabled(currentUserPerson == nil)

                Spacer()

                if !selectedParticipants.isEmpty {
                    Button(action: {
                        selectedParticipants.removeAll()
                        customAmounts.removeAll()
                    }) {
                        Text("Clear")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.red)
                }
            }
            .padding(.vertical, 4)

            // Participant list
            ForEach(viewModel.people) { person in
                participantRow(for: person)
            }
        } header: {
            Text("Split Between (\(selectedParticipants.count) selected)")
        }
    }
    
    @ViewBuilder
    private func participantRow(for person: Person) -> some View {
        Button {
            toggleParticipant(person)
        } label: {
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
            .padding(.vertical, 4)
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
    private var receiptSection: some View {
        if mode == .manual {
            Section {
                Button(action: { showingReceiptScanner = true }) {
                    HStack(spacing: 12) {
                        Image(systemName: "doc.text.viewfinder")
                            .font(.title2)
                            .foregroundColor(.blue)
                            .frame(width: 24, height: 24)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Scan Receipt")
                            .font(.body)
                            .foregroundColor(.primary)
                        Text("Auto-split by items")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)

                ReceiptAttachmentView(receiptImages: $receiptImages)
            } header: {
                Text("Receipt")
            } footer: {
                Text("Scan receipts to automatically split by individual items.")
                    .font(.caption)
            }
        }
    }

    // MARK: - Actions
    private func joinExpenseFlow() {
        guard isValid else { return }
        addExpense()
    }
    
    private func addExpense() {
        guard let amountValue = decimal(from: amount),
              let payer = currentUserPerson else { return }
        
        isConverting = true
        
        Task {
            defer {
                Task { @MainActor in
                    isConverting = false
                }
            }
            
            print("💰 Creating new expense: \(description)")
            let expenseDescription = description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? defaultQuickDescription : description
            var expense = Expense(
                description: expenseDescription,
                originalAmount: amountValue,
                originalCurrency: selectedCurrency,
                baseCurrency: viewModel.trip.baseCurrency,
                exchangeRate: currentExchangeRate,
                paidBy: payer,
                participants: viewModel.people.filter { selectedParticipants.contains($0.id) }
            )
            
            let resolvedSplitType: SplitType = mode == .quick ? .equal : splitType
            expense.splitType = resolvedSplitType
            
            if resolvedSplitType == .custom {
                let splits = customAmounts.compactMap { key, value -> (UUID, Decimal)? in
                    guard selectedParticipants.contains(key), let decimalValue = decimal(from: value) else { return nil }
                    return (key, decimalValue)
                }
                expense.customSplits = Dictionary(uniqueKeysWithValues: splits)
            }

            if let creatorId = profileManager.currentProfile?.id {
                expense.createdByUserId = creatorId
            }
            
            if !receiptImages.isEmpty {
                print("📸 Uploading \(receiptImages.count) receipt photos…")
                await MainActor.run {
                    viewModel.receiptImages = receiptImages
                }
                let uploadedUrls = await viewModel.uploadReceipts(for: expense)
                expense.receiptImageIds = uploadedUrls
                await MainActor.run {
                    viewModel.receiptImages.removeAll()
                }
                print("📎 Attached \(uploadedUrls.count) receipt URLs to expense")
            } else {
                print("📝 No receipts to upload")
            }
            
            await MainActor.run {
                viewModel.addExpense(expense)
                lastExpenseTemplate = expense
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
            }
        }
    }
    
    private func toggleParticipant(_ person: Person) {
        if selectedParticipants.contains(person.id) {
            selectedParticipants.remove(person.id)
            customAmounts.removeValue(forKey: person.id)
        } else {
            selectedParticipants.insert(person.id)
            if splitType == .custom {
                customAmounts[person.id] = ""
            }
        }
    }
    
    // MARK: - Setup Helpers
    private func configureView() {
        selectedCurrency = profileManager.currentProfile?.preferredCurrency ?? viewModel.trip.baseCurrency
        lastExpenseTemplate = viewModel.expenses.last
        applyInitialDefaultsIfNeeded()
        updateExchangeRate()
        focusedField = mode == .quick ? .amount : .description
    }

    private func applyInitialDefaultsIfNeeded() {
        guard !hasAppliedInitialDefaults else { return }
        defer { hasAppliedInitialDefaults = true }
        
        if selectedParticipants.isEmpty {
            selectedParticipants = Set(viewModel.people.map(\.id))
        }

        if mode == .quick {
            splitType = .equal
        }

        if splitType == .custom {
            for id in selectedParticipants where customAmounts[id] == nil {
                customAmounts[id] = ""
            }
        }
    }
    
    private func syncSelection(with people: [Person]) {
        let allIds = Set(people.map(\.id))
        selectedParticipants = selectedParticipants.intersection(allIds)
        if selectedParticipants.isEmpty {
            selectedParticipants = allIds
        }
        
        customAmounts = customAmounts.filter { allIds.contains($0.key) }
        if splitType == .custom {
            for id in selectedParticipants where customAmounts[id] == nil {
                customAmounts[id] = ""
            }
        }
    }
    
    private func handleSplitTypeChange(_ newValue: SplitType) {
        switch newValue {
        case .custom:
            for id in selectedParticipants where customAmounts[id] == nil {
                customAmounts[id] = ""
            }
        default:
            customAmounts.removeAll()
        }
    }
    
    private func applyTemplate(_ template: Expense) {
        description = template.description
        amount = formatForInput(template.originalAmount)
        selectedCurrency = template.originalCurrency
        currentExchangeRate = template.exchangeRate
        splitType = template.splitType
        selectedParticipants = Set(template.participants.compactMap { participant in
            viewModel.people.first(where: { $0.id == participant.id })?.id ?? participant.id
        })
        if selectedParticipants.isEmpty {
            selectedParticipants = Set(viewModel.people.map(\.id))
        }
        customAmounts.removeAll()
        if template.splitType == .custom {
            for (id, value) in template.customSplits {
                customAmounts[id] = formatForInput(value)
            }
        }
        
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    
    private func updateExchangeRate() {
        guard selectedCurrency != viewModel.trip.baseCurrency else {
            currentExchangeRate = Decimal(1)
            isLoadingRate = false
            return
        }
        
        isLoadingRate = true
        Task {
            let rate = await currencyService.getExchangeRate(from: selectedCurrency, to: viewModel.trip.baseCurrency)
            await MainActor.run {
                currentExchangeRate = rate
                isLoadingRate = false
            }
        }
    }
    
    // MARK: - Formatting Helpers
    private func decimal(from text: String) -> Decimal? {
        let cleaned = text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)
        return Decimal(string: cleaned)
    }

    private func formatForInput(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.locale = Locale.current
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? NSDecimalNumber(decimal: value).stringValue
    }

    private var currentUserPerson: Person? {
        guard let profile = profileManager.currentProfile else { return nil }
        return viewModel.people.first(where: { $0.id == profile.id })
    }

    private var payerDisplayName: String {
        currentUserPerson?.name ?? "Your profile"
    }

    private var defaultQuickDescription: String {
        "New expense"
    }

    @ViewBuilder
    private var quickAmountSection: some View {
        if mode == .quick {
            Section("Quick Amounts") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(quickAmountSuggestions, id: \.self) { suggestion in
                            Button(action: { applyQuickAmount(suggestion) }) {
                                Text(CurrencyAmount(amount: suggestion, currency: selectedCurrency).formatted())
                                    .font(.caption)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.blue.opacity(0.12))
                                    .foregroundColor(.blue)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func applyQuickAmount(_ value: Decimal) {
        amount = formatForInput(value)
    }
}
