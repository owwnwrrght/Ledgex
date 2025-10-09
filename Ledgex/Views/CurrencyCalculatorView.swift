import SwiftUI

struct CurrencyCalculatorView: View {
    @StateObject private var exchangeService = CurrencyExchangeService.shared
    @State private var amount: String = "100"
    @State private var fromCurrency: Currency = .USD
    @State private var toCurrency: Currency = .EUR
    @State private var convertedAmount: Decimal = 0
    @State private var isCalculating = false
    
    var body: some View {
        NavigationView {
            Form {
                Section("Amount") {
                    HStack {
                        TextField("Amount", text: $amount)
                            .keyboardType(.decimalPad)
                        Picker("From", selection: $fromCurrency) {
                            ForEach(Currency.allCases, id: \.self) { currency in
                                Text(currency.displayName).tag(currency)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
                
                Section("Convert To") {
                    Picker("Currency", selection: $toCurrency) {
                        ForEach(Currency.allCases, id: \.self) { currency in
                            Text(currency.displayName).tag(currency)
                        }
                    }
                    .pickerStyle(.menu)
                }
                
                Section("Result") {
                    if isCalculating {
                        HStack {
                            ProgressView()
                            Text("Calculating...")
                        }
                    } else {
                        HStack {
                            Text("Converted Amount")
                            Spacer()
                            Text(CurrencyAmount(amount: convertedAmount, currency: toCurrency).formatted())
                                .font(.headline)
                        }
                        
                        if let rate = exchangeService.getCachedRate(from: fromCurrency, to: toCurrency) {
                            HStack {
                                Text("Exchange Rate")
                                Spacer()
                                Text("1 \(fromCurrency.rawValue) = \(NSDecimalNumber(decimal: rate).doubleValue, specifier: "%.4f") \(toCurrency.rawValue)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                Button(action: calculate) {
                    Label("Calculate", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(amount.isEmpty || isCalculating)
                
                if let lastUpdated = exchangeService.lastUpdated {
                    Section {
                        HStack {
                            Text("Rates updated")
                            Spacer()
                            Text(lastUpdated, style: .relative)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Currency Calculator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Swap") {
                        let temp = fromCurrency
                        fromCurrency = toCurrency
                        toCurrency = temp
                        calculate()
                    }
                }
            }
        }
        .onAppear {
            calculate()
        }
    }
    
    private func calculate() {
        guard let amountDecimal = Decimal(string: amount) else { return }
        
        isCalculating = true
        Task {
            convertedAmount = await exchangeService.convert(amount: amountDecimal, from: fromCurrency, to: toCurrency)
            isCalculating = false
        }
    }
}