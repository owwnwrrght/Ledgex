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
            let result = try await functions.httpsCallable("processReceiptImage").call(["image": base64Image])
            
            // 3. Decode the result from the function
            guard let data = result.data as? [String: Any], let rawText = data["rawText"] as? String else {
                throw AppError(message: "Invalid response from server.")
            }

            // 4. Parse the raw text into an OCRResult
            // This parsing logic should be robust. For this example, we'll create a placeholder.
            // You should replace this with the actual parsing logic you had or a new, improved one.
            let parsedResult = parseOCRResponse(rawText: rawText)
            
            return parsedResult
        } catch {
            print("Error calling Firebase Function: \(error.localizedDescription)")
            throw AppError.make(from: error, fallbackTitle: "Receipt Scan Failed", fallbackMessage: "Could not process the receipt image. Please try again.")
        }
    }

    // This is a placeholder for the complex parsing logic.
    // You would need to implement this to match your app's requirements for extracting
    // items, prices, merchant names, etc., from the raw text returned by the Vision API.
    private func parseOCRResponse(rawText: String) -> OCRResult {
        // TODO: Implement robust parsing of the raw text from the Vision API.
        // For now, returning a dummy result.
        print("--- OCR Raw Text ---")
        print(rawText)
        print("--------------------")
        
        let dummyItems = [ReceiptItem(name: "Scanned Item 1", quantity: 1, price: 12.99),
                          ReceiptItem(name: "Scanned Item 2", quantity: 2, price: 5.50)]
        
        return OCRResult(
            items: dummyItems,
            merchantName: "Scanned Merchant",
            totalAmount: 24.00,
            tax: 1.01,
            tip: 0,
            detectedLanguage: "en"
        )
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
