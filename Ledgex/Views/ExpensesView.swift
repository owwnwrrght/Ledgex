import SwiftUI

struct ExpensesView: View {
    @ObservedObject var viewModel: ExpenseViewModel
    @State private var expenseToEdit: Expense?
    @State private var processingDone = false
    @State private var selectedCategoryFilter: ExpenseCategory? = nil
    
    private var filteredExpenses: [Expense] {
        if let category = selectedCategoryFilter {
            return viewModel.expenses.filter { $0.category == category }
        }
        return viewModel.expenses
    }

    private var totalExpenses: Decimal {
        filteredExpenses.reduce(Decimal.zero) { $0 + $1.amount }
    }
    
    private var totalExpensesSummary: some View {
        HStack(spacing: 16) {
            Image(systemName: "chart.bar.fill")
                .font(.title)
                .foregroundColor(.blue)

            VStack(alignment: .leading, spacing: 4) {
                Text("Total Expenses")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(CurrencyAmount(amount: totalExpenses, currency: viewModel.trip.baseCurrency).formatted())
                    .font(.title2)
                    .fontWeight(.bold)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(viewModel.expenses.count)")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("item\(viewModel.expenses.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 12)
    }
    
    private var itemWrapperBinding: Binding<ItemWrapper?> {
        Binding(
            get: { 
                if let pendingExpense = viewModel.pendingItemizedExpense {
                    return ItemWrapper(value: pendingExpense)
                }
                return nil
            },
            set: { _ in 
                viewModel.pendingItemizedExpense = nil 
            }
        )
    }
    
    var body: some View {
        VStack(spacing: 0) {
            mainContent
                .listStyle(.insetGrouped)
                .sheet(item: $expenseToEdit) { expense in
                    EditExpenseView(expense: expense, viewModel: viewModel)
                }
                .sheet(item: itemWrapperBinding) { wrapper in
                    ItemizedExpenseView(
                        viewModel: viewModel,
                        receiptImage: wrapper.value.0,
                        ocrResult: wrapper.value.1
                    )
                }
                .overlay {
                    emptyStateView
                }

            doneButton
        }
    }
    
    private var mainContent: some View {
        List {
            if !filteredExpenses.isEmpty {
                Section {
                    totalExpensesSummary
                }
            }

            if !filteredExpenses.isEmpty {
                Section {
                    ForEach(filteredExpenses) { expense in
                        ExpenseRow(expense: expense, baseCurrency: viewModel.trip.baseCurrency, dataStore: FirebaseManager.shared)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                expenseToEdit = expense
                            }
                    }
                    .onDelete { indexSet in
                        if selectedCategoryFilter == nil {
                            viewModel.removeExpense(at: indexSet)
                        } else {
                            let originalIndexes = IndexSet(indexSet.compactMap { index in
                                viewModel.expenses.firstIndex(where: { $0.id == filteredExpenses[index].id })
                            })
                            viewModel.removeExpense(at: originalIndexes)
                        }
                    }
                } header: {
                    Text("Expenses")
                }
            }
        }
    }
    
    
    @ViewBuilder
    private var emptyStateView: some View {
        if filteredExpenses.isEmpty {
            VStack(spacing: 20) {
                Image(systemName: viewModel.isInSetupPhase ? "person.3.fill" : "dollarsign.circle")
                    .font(.system(size: 60))
                    .foregroundColor(viewModel.isInSetupPhase ? .blue : .gray)

                VStack(spacing: 8) {
                    Text(viewModel.isInSetupPhase ? "Group Setup" : "No Expenses")
                        .font(.title2)

                    if viewModel.isInSetupPhase {
                        Text("Add all participants in the People tab, then start the group to begin adding expenses.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    } else if viewModel.people.isEmpty {
                        Text("Add people to your group first, then you can start tracking expenses.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    } else {
                        Text("Start by adding your first expense or scanning a receipt.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }

            }
            .padding()
        }
    }

    private var currentUserPerson: Person? {
        viewModel.people.first(where: viewModel.isCurrentUser)
    }

    private var canToggleCompletion: Bool {
        guard let person = currentUserPerson else { return false }
        return viewModel.canToggleCompletion(for: person)
    }

    private var hasCompletedExpenses: Bool {
        currentUserPerson?.hasCompletedExpenses ?? false
    }

    private var doneButton: some View {
        Group {
            if canToggleCompletion && !viewModel.expenses.isEmpty {
                VStack(spacing: 16) {
                    Button(action: {
                        guard let person = currentUserPerson else { return }
                        processingDone = true
                        Task {
                            await viewModel.toggleCompletion(for: person)
                            await MainActor.run {
                                processingDone = false
                            }
                        }
                    }) {
                        HStack(spacing: 12) {
                            if processingDone {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: hasCompletedExpenses ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                            }
                            Text(hasCompletedExpenses ? "I'm Done Adding Expenses" : "Tap When Done Adding Expenses")
                                .font(.headline)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(hasCompletedExpenses ? Color.green : Color.blue)
                        .cornerRadius(12)
                    }
                    .disabled(processingDone)
                    .padding(.horizontal)
                    .padding(.bottom)
                }
            }
        }
    }
}

struct ExpenseRow: View {
    let expense: Expense
    let baseCurrency: Currency
    let dataStore: TripDataStore

    private var splitDescription: String {
        switch expense.splitType {
        case .equal:
            return "Split equally • \(expense.participants.count) people"
        case .itemized:
            return "Itemized • \(expense.receiptItems.count) items"
        case .custom:
            return "Custom split • \(expense.participants.count) people"
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: expense.category.icon)
                .foregroundColor(.blue)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(expense.description)
                        .font(.body)
                        .fontWeight(.semibold)

                    if expense.hasReceipt {
                        Image(systemName: "doc.text.fill")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                }

                HStack(spacing: 6) {
                    Text("Paid by")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(expense.paidBy.name)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    Text("•")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(expense.date, style: .date)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text(splitDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let conversionInfo = expense.conversionInfo {
                    Text(conversionInfo)
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }

            Spacer()

            Text(expense.originalAmountFormatted)
                .font(.body)
                .fontWeight(.bold)
                .foregroundColor(.primary)
        }
        .padding(.vertical, 4)
    }
}
