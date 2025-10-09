import Foundation
import SwiftUI
import Combine

// MARK: - Exchange Rate Model
struct ExchangeRate: Codable {
    let from: Currency
    let to: Currency
    let rate: Decimal
    let timestamp: Date
    
    var isExpired: Bool {
        // Consider rates older than 24 hours as expired
        return Date().timeIntervalSince(timestamp) > 86400
    }
}

// MARK: - Currency Exchange Service
class CurrencyExchangeService: ObservableObject {
    @MainActor static let shared = CurrencyExchangeService()
    
    @MainActor @Published var isLoading = false
    @MainActor @Published var lastUpdated: Date?
    @MainActor @Published var exchangeRates: [String: ExchangeRate] = [:]
    
    // New: Historical rates for specific dates
    @MainActor @Published var historicalRates: [String: [Date: Decimal]] = [:]
    
    private let cacheKey = "CachedExchangeRates"
    private let historicalCacheKey = "CachedHistoricalRates"
    
    init() {
        Task { @MainActor in
            loadCachedRates()
        }
    }
    
    // Get exchange rate, fetch if needed
    @MainActor func getExchangeRate(from: Currency, to: Currency) async -> Decimal {
        if from == to { return Decimal(1) }
        
        let key = "\(from.rawValue)_\(to.rawValue)"
        
        // Check cache first
        if let cachedRate = exchangeRates[key], !cachedRate.isExpired {
            return cachedRate.rate
        }
        
        // Fetch new rate
        await fetchExchangeRate(from: from, to: to)
        return exchangeRates[key]?.rate ?? Decimal(1)
    }
    
    // Get cached exchange rate (synchronous)
    @MainActor func getCachedRate(from: Currency, to: Currency) -> Decimal? {
        if from == to { return Decimal(1) }
        
        let key = "\(from.rawValue)_\(to.rawValue)"
        return exchangeRates[key]?.rate
    }
    
    // Convert amount between currencies
    func convert(amount: Decimal, from: Currency, to: Currency) async -> Decimal {
        if from == to { return amount }
        
        let rate = await getExchangeRate(from: from, to: to)
        return amount * rate
    }
    
    // New: Get historical rate for a specific date
    @MainActor func getHistoricalRate(from: Currency, to: Currency, date: Date) async -> Decimal {
        if from == to { return Decimal(1) }
        
        let key = "\(from.rawValue)_\(to.rawValue)"
        let dateKey = Calendar.current.startOfDay(for: date)
        
        // Check cache first
        if let cachedRates = historicalRates[key],
           let rate = cachedRates[dateKey] {
            return rate
        }
        
        // Fetch historical rate
        await fetchHistoricalRate(from: from, to: to, date: date)
        return historicalRates[key]?[dateKey] ?? Decimal(1)
    }
    
    // Fetch exchange rate from API (using a free service)
    @MainActor private func fetchExchangeRate(from: Currency, to: Currency) async {
        isLoading = true
        
        do {
            // Using exchangerate-api.com (free tier: 1500 requests/month)
            let urlString = "https://api.exchangerate-api.com/v4/latest/\(from.rawValue)"
            guard let url = URL(string: urlString) else { return }
            
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            
            let (data, _) = try await URLSession.shared.data(for: request)
            
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let rates = json["rates"] as? [String: Double],
               let targetRate = rates[to.rawValue] {
                
                let rate = ExchangeRate(
                    from: from,
                    to: to,
                    rate: Decimal(targetRate),
                    timestamp: Date()
                )
                
                let key = "\(from.rawValue)_\(to.rawValue)"
                self.exchangeRates[key] = rate
                self.lastUpdated = Date()
                self.saveCachedRates()
            }
        } catch {
            print("Failed to fetch exchange rate: \(error)")
            // Fallback to 1:1 rate if API fails
            let key = "\(from.rawValue)_\(to.rawValue)"
            self.exchangeRates[key] = ExchangeRate(
                from: from,
                to: to,
                rate: Decimal(1),
                timestamp: Date()
            )
        }
        
        isLoading = false
    }
    
    // New: Fetch historical exchange rate
    @MainActor private func fetchHistoricalRate(from: Currency, to: Currency, date: Date) async {
        do {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let dateString = dateFormatter.string(from: date)
            
            // Using exchangerate-api.com historical endpoint
            let urlString = "https://api.exchangerate-api.com/v4/history/\(from.rawValue)/\(dateString)"
            guard let url = URL(string: urlString) else { return }
            
            let (data, _) = try await URLSession.shared.data(from: url)
            
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let rates = json["rates"] as? [String: Double],
               let targetRate = rates[to.rawValue] {
                
                let key = "\(from.rawValue)_\(to.rawValue)"
                let dateKey = Calendar.current.startOfDay(for: date)
                
                if historicalRates[key] == nil {
                    historicalRates[key] = [:]
                }
                historicalRates[key]?[dateKey] = Decimal(targetRate)
                
                saveHistoricalRates()
            }
        } catch {
            print("Failed to fetch historical rate: \(error)")
        }
    }
    
    // Cache management
    @MainActor private func saveCachedRates() {
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(Array(exchangeRates.values)) {
            UserDefaults.standard.set(encoded, forKey: cacheKey)
        }
    }
    
    @MainActor private func loadCachedRates() {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return }
        
        let decoder = JSONDecoder()
        if let rates = try? decoder.decode([ExchangeRate].self, from: data) {
            exchangeRates = rates.reduce(into: [:]) { dict, rate in
                let key = "\(rate.from.rawValue)_\(rate.to.rawValue)"
                dict[key] = rate
            }
            
            lastUpdated = rates.map { $0.timestamp }.max()
        }
    }
    
    @MainActor private func saveHistoricalRates() {
        // Simple implementation - in production, you'd want to limit cache size
        UserDefaults.standard.set(try? JSONEncoder().encode(historicalRates), forKey: historicalCacheKey)
    }
    
    // Prefetch common currency pairs
    func prefetchCommonRates(for baseCurrency: Currency) async {
        let commonCurrencies: [Currency] = [.USD, .EUR, .GBP, .JPY, .CAD]
        
        for currency in commonCurrencies where currency != baseCurrency {
            _ = await getExchangeRate(from: baseCurrency, to: currency)
        }
    }
}