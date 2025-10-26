import SwiftUI

struct ExpenseEntryFlowView: View {
    @ObservedObject var viewModel: ExpenseViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var path: [Destination] = []

    private enum Destination: Hashable {
        case manual
        case scan
    }

    var body: some View {
        NavigationStack(path: $path) {
            optionList
                .navigationTitle("Add Expense")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
                .navigationDestination(for: Destination.self) { destination in
                    switch destination {
                    case .manual:
                        AddExpenseView(viewModel: viewModel, embedInNavigationView: false)
                            .navigationTitle("Enter Manually")
                            .navigationBarTitleDisplayMode(.inline)
                    case .scan:
                        ReceiptScannerView(
                            viewModel: viewModel,
                            embedInNavigationView: false,
                            onCancel: {
                                if !path.isEmpty {
                                    path.removeLast()
                                } else {
                                    dismiss()
                                }
                            },
                            onComplete: { image, result in
                                viewModel.pendingItemizedExpense = (image, result)
                                dismiss()
                            }
                        )
                        .navigationTitle("Scan Receipt")
                        .navigationBarTitleDisplayMode(.inline)
                    }
                }
        }
    }

    private var optionList: some View {
        List {
            Section("How would you like to add an expense?") {
                NavigationLink(value: Destination.manual) {
                    optionRow(
                        title: "Enter manually",
                        message: "Type in the amount and choose who participated."
                    )
                }

                NavigationLink(value: Destination.scan) {
                    optionRow(
                        title: "Scan a receipt",
                        message: "Use the camera or photo library to capture a bill and auto-split by items."
                    )
                }
            }

            Section {
                Text("You can rescan a receipt at any time from the itemized expense editor.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .listStyle(.insetGrouped)
    }

    private func optionRow(title: String, message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: title.contains("Scan") ? "doc.text.viewfinder" : "pencil")
                .font(.title3)
                .foregroundColor(.accentColor)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
    }
}
