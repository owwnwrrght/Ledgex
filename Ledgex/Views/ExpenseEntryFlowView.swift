import SwiftUI

struct ExpenseEntryFlowView: View {
    @ObservedObject var viewModel: ExpenseViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            AddExpenseView(viewModel: viewModel, embedInNavigationView: false)
                .navigationTitle("Add Expense")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
        }
    }
}
