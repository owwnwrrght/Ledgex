import Foundation

enum Currency: String, CaseIterable, Codable {
    case USD = "USD"
    case EUR = "EUR"
    case GBP = "GBP"
    case JPY = "JPY"
    case CAD = "CAD"
    case AUD = "AUD"
    case CHF = "CHF"
    case CNY = "CNY"
    case INR = "INR"
    case KRW = "KRW"
    case MXN = "MXN"
    case BRL = "BRL"
    case SEK = "SEK"
    case NOK = "NOK"
    case DKK = "DKK"
    case PLN = "PLN"
    case THB = "THB"
    case IDR = "IDR"
    case HUF = "HUF"
    case CZK = "CZK"
    case ILS = "ILS"
    case CLP = "CLP"
    case PHP = "PHP"
    case AED = "AED"
    case COP = "COP"
    case SAR = "SAR"
    case MYR = "MYR"
    case RON = "RON"
    
    var symbol: String {
        switch self {
        case .USD: return "$"
        case .EUR: return "€"
        case .GBP: return "£"
        case .JPY: return "¥"
        case .CAD: return "C$"
        case .AUD: return "A$"
        case .CHF: return "CHF"
        case .CNY: return "¥"
        case .INR: return "₹"
        case .KRW: return "₩"
        case .MXN: return "$"
        case .BRL: return "R$"
        case .SEK: return "kr"
        case .NOK: return "kr"
        case .DKK: return "kr"
        case .PLN: return "zł"
        case .THB: return "฿"
        case .IDR: return "Rp"
        case .HUF: return "Ft"
        case .CZK: return "Kč"
        case .ILS: return "₪"
        case .CLP: return "$"
        case .PHP: return "₱"
        case .AED: return "د.إ"
        case .COP: return "$"
        case .SAR: return "﷼"
        case .MYR: return "RM"
        case .RON: return "lei"
        }
    }
    
    var flag: String {
        switch self {
        case .USD: return "🇺🇸"
        case .EUR: return "🇪🇺"
        case .GBP: return "🇬🇧"
        case .JPY: return "🇯🇵"
        case .CAD: return "🇨🇦"
        case .AUD: return "🇦🇺"
        case .CHF: return "🇨🇭"
        case .CNY: return "🇨🇳"
        case .INR: return "🇮🇳"
        case .KRW: return "🇰🇷"
        case .MXN: return "🇲🇽"
        case .BRL: return "🇧🇷"
        case .SEK: return "🇸🇪"
        case .NOK: return "🇳🇴"
        case .DKK: return "🇩🇰"
        case .PLN: return "🇵🇱"
        case .THB: return "🇹🇭"
        case .IDR: return "🇮🇩"
        case .HUF: return "🇭🇺"
        case .CZK: return "🇨🇿"
        case .ILS: return "🇮🇱"
        case .CLP: return "🇨🇱"
        case .PHP: return "🇵🇭"
        case .AED: return "🇦🇪"
        case .COP: return "🇨🇴"
        case .SAR: return "🇸🇦"
        case .MYR: return "🇲🇾"
        case .RON: return "🇷🇴"
        }
    }
    
    var displayName: String {
        "\(flag) \(symbol) \(rawValue)"
    }
}

// Helper struct for currency amounts
struct CurrencyAmount {
    let amount: Decimal
    let currency: Currency
    
    func formatted() -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency.rawValue
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        
        // For currencies that don't use decimals (like JPY)
        switch currency {
        case .JPY, .KRW, .IDR, .CLP, .HUF:
            formatter.minimumFractionDigits = 0
            formatter.maximumFractionDigits = 0
        default:
            break
        }
        
        if let formattedAmount = formatter.string(from: NSDecimalNumber(decimal: amount)) {
            return formattedAmount
        }
        
        // Fallback to manual formatting if NumberFormatter fails for any reason
        let fallbackAmount = NSDecimalNumber(decimal: amount).doubleValue
        if formatter.maximumFractionDigits == 0 {
            return "\(currency.symbol)\(Int(fallbackAmount))"
        } else {
            return String(format: "%@%.2f", currency.symbol, fallbackAmount)
        }
    }
}
