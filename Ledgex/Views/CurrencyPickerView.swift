import SwiftUI

struct CurrencyPickerView: View {
    @Binding var selectedCurrency: Currency
    @Environment(\.dismiss) var dismiss
    @State private var searchText = ""
    
    var filteredCurrencies: [Currency] {
        if searchText.isEmpty {
            return Currency.allCases
        } else {
            return Currency.allCases.filter { currency in
                currency.rawValue.localizedCaseInsensitiveContains(searchText) ||
                currency.displayName.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        NavigationView {
            List {
                ForEach(filteredCurrencies, id: \.self) { currency in
                    Button(action: {
                        selectedCurrency = currency
                        dismiss()
                    }) {
                        HStack {
                            Text(currency.displayName)
                                .foregroundColor(.primary)
                            Spacer()
                            if currency == selectedCurrency {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Currency")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search currencies")
        }
    }
}