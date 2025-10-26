import SwiftUI
import FirebaseFunctions

// MARK: - OCR Result
struct OCRResult {
    let items: [ReceiptItem]
    let merchantName: String?
    let totalAmount: Decimal?
    let tax: Decimal
    let tip: Decimal
    let detectedLanguage: String?
}

// MARK: - Receipt Item
struct ReceiptItem: Identifiable, Codable {
    var id = UUID()
    var name: String
    var quantity: Int
    var price: Decimal
    var totalPrice: Decimal { price * Decimal(quantity) }
    var selectedBy: Set<UUID> = []
    
    var pricePerPerson: Decimal {
        guard !selectedBy.isEmpty else { return 0 }
        return totalPrice / Decimal(selectedBy.count)
    }
}

class GoogleCloudVisionService {
    static let shared = GoogleCloudVisionService()
    lazy var functions = Functions.functions()

    private init() {}

    func processReceipt(image: UIImage) async throws -> OCRResult {
        // 1. Convert UIImage to Base64 encoded string
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw AppError(message: "Failed to convert image to data.")
        }
        let base64Image = imageData.base64EncodedString()

        // 2. Call the Firebase Function
        do {
            print("📸 Sending receipt image to server for processing...")
            let result = try await functions.httpsCallable("processReceiptImage").call(["image": base64Image])

            // 3. Decode the result from the function
            guard let data = result.data as? [String: Any] else {
                print("❌ Invalid response from server: \(result.data)")
                throw AppError(message: "Invalid response from server.")
            }

            print("✅ Received response from server")

            // 4. Parse the structured result returned by the server
            let parsedResult = try parseServerResponse(data)

            print("✅ Successfully parsed \(parsedResult.items.count) items from receipt")

            return parsedResult
        } catch let error as NSError {
            print("❌ Error calling Firebase Function: \(error)")
            print("   Error code: \(error.code)")
            print("   Error domain: \(error.domain)")
            print("   Error description: \(error.localizedDescription)")

            // Check for specific Firebase Function error codes
            if let errorCode = error.userInfo["code"] as? String {
                print("   Firebase error code: \(errorCode)")

                switch errorCode {
                case "failed-precondition":
                    throw AppError(
                        title: "Configuration Error",
                        message: "The receipt scanning service is not properly configured. Please contact support."
                    )
                case "resource-exhausted":
                    throw AppError(
                        title: "Too Many Requests",
                        message: "The service is experiencing high traffic. Please try again in a moment."
                    )
                case "unavailable":
                    throw AppError(
                        title: "Service Unavailable",
                        message: "Could not reach the receipt processing service. Please check your internet connection and try again."
                    )
                case "unauthenticated":
                    throw AppError(
                        title: "Authentication Error",
                        message: "You must be signed in to scan receipts. Please sign in and try again."
                    )
                default:
                    break
                }
            }

            // Extract error message from Firebase error if available
            if let errorMessage = error.userInfo["message"] as? String {
                throw AppError(
                    title: "Receipt Scan Failed",
                    message: errorMessage
                )
            }

            throw AppError.make(from: error, fallbackTitle: "Receipt Scan Failed", fallbackMessage: "Could not process the receipt image. Please ensure the receipt is clearly visible and try again with better lighting.")
        }
    }

    private func parseServerResponse(_ payload: [String: Any]) throws -> OCRResult {
        let merchantName = payload["merchantName"] as? String
        let tax = decimal(from: payload["tax"]) ?? 0
        let tip = decimal(from: payload["tip"]) ?? 0
        let total = decimal(from: payload["total"]) ?? decimal(from: payload["subtotal"])
        
        let items: [ReceiptItem] = (payload["items"] as? [[String: Any]])?.compactMap { itemDict in
            guard let name = (itemDict["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty else { return nil }
            
            let quantity = quantity(from: itemDict["quantity"])
            let price = decimal(from: itemDict["price"]) ?? 0
            
            return ReceiptItem(name: name, quantity: quantity, price: price)
        } ?? []
        
        guard !items.isEmpty else {
            throw AppError(message: "We couldn't find any items on that receipt. Please try again with a clearer photo.")
        }
        
        return OCRResult(
            items: items,
            merchantName: merchantName,
            totalAmount: total,
            tax: tax,
            tip: tip,
            detectedLanguage: nil
        )
    }
    
    private func decimal(from value: Any?) -> Decimal? {
        switch value {
        case let number as NSNumber:
            return number.decimalValue
        case let string as String:
            if let doubleValue = Double(string) {
                return Decimal(doubleValue)
            }
            return nil
        case let doubleValue as Double:
            return Decimal(doubleValue)
        case let intValue as Int:
            return Decimal(intValue)
        default:
            return nil
        }
    }
    
    private func quantity(from value: Any?) -> Int {
        if let number = value as? NSNumber {
            return max(Int(number.doubleValue.rounded()), 1)
        }
        
        if let string = value as? String, let doubleValue = Double(string) {
            return max(Int(doubleValue.rounded()), 1)
        }
        
        if let doubleValue = value as? Double {
            return max(Int(doubleValue.rounded()), 1)
        }
        
        if let intValue = value as? Int {
            return max(intValue, 1)
        }
        
        return 1
    }
}
// MARK: - Error Types
enum OCRError: LocalizedError {
    case imageConversionFailed
    case invalidURL
    case requestFailed(String)
    case parsingFailed(String)
    case configurationMissing
    case featureDisabled
    case networkError(String)
    case apiError(Int, String)
    case noTextDetected
    
    var errorDescription: String? {
        switch self {
        case .imageConversionFailed:
            return "Failed to convert image for processing"
        case .invalidURL:
            return "Invalid API URL"
        case .requestFailed(let details):
            return "API request failed: \(details)"
        case .parsingFailed(let details):
            return "Failed to parse response: \(details)"
        case .configurationMissing:
            return "API keys not configured. Please check your settings."
        case .featureDisabled:
            return "Receipt scanning is currently disabled"
        case .networkError(let details):
            return "Network connection failed: \(details)"
        case .apiError(let code, let message):
            return "API Error (\(code)): \(message)"
        case .noTextDetected:
            return "No text could be detected in the image. Please ensure the receipt is clear and well-lit."
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .networkError:
            return "Please check your internet connection and try again."
        case .noTextDetected:
            return "Try taking another photo with better lighting or ensure the entire receipt is visible."
        case .configurationMissing:
            return "Please configure your API keys in the app settings."
        case .apiError(let code, _):
            if code == 403 {
                return "API quota exceeded or invalid API key. Please check your Google Cloud settings."
            } else if code >= 500 {
                return "Google's servers are temporarily unavailable. Please try again later."
            } else {
                return "Please try again or contact support if the problem persists."
            }
        default:
            return "Please try again. If the problem persists, contact support."
        }
    }
}
