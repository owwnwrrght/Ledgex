import Foundation
import UIKit

// MARK: - Receipt Item Model
struct ReceiptItem: Identifiable, Codable {
    var id = UUID()
    var name: String
    var originalName: String // Original text before translation
    var price: Decimal
    var quantity: Int = 1
    var selectedBy: Set<UUID> = [] // Person IDs who selected this item
    
    var totalPrice: Decimal {
        price * Decimal(quantity)
    }
    
    var pricePerPerson: Decimal {
        guard !selectedBy.isEmpty else { return 0 }
        return totalPrice / Decimal(selectedBy.count)
    }
}

// MARK: - OCR Result Model
struct OCRResult {
    let fullText: String
    let detectedLanguage: String?
    let items: [ReceiptItem]
    let totalAmount: Decimal?
    let merchantName: String?
    let date: Date?
    let tax: Decimal
    let tip: Decimal
}

// MARK: - AI Receipt Processing Service
class GoogleCloudVisionService {
    static let shared = GoogleCloudVisionService()
    
    private let openAIURL = "https://api.openai.com/v1/chat/completions"
    
    private init() {
        // Uses OpenAI Vision API for receipt processing
    }
    
    // MARK: - Configuration Validation
    
    private func validateConfiguration() throws {
        // Only need OpenAI API key now
        _ = APIKeyManager.shared.openAIKey // This will throw if key is missing
        print("✅ OpenAI API key found")
    }
    
    // MARK: - Main Receipt Processing Function
    func processReceipt(image: UIImage) async throws -> OCRResult {
        print("📷 Starting OpenAI vision-based receipt processing...")
        
        // Use OpenAI Vision directly for both OCR and parsing
        return try await processReceiptWithOpenAIVision(image: image)
    }
    
    
    
    
    // MARK: - OpenAI Vision Receipt Processing
    private func processReceiptWithOpenAIVision(image: UIImage) async throws -> OCRResult {
        let openAIKey = APIKeyManager.shared.openAIKey
        
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw OCRError.imageConversionFailed
        }
        
        let base64Image = imageData.base64EncodedString()
        print("📷 Image converted to base64, size: \(base64Image.count) characters")
        
        return try await requestOpenAIVisionParsing(base64Image: base64Image, apiKey: openAIKey)
    }
    
    
    private func requestOpenAIVisionParsing(base64Image: String, apiKey: String) async throws -> OCRResult {
        let systemPrompt = """
        You are a receipt parser that analyzes receipt images and extracts food/beverage items plus tax and tip for expense splitting.
        
        EXTRACT:
        - Food items (burgers, pizza, salad, appetizers, entrees, desserts, etc.)
        - Beverages (soda, coffee, beer, wine, cocktails, etc.)
        - Item quantities if mentioned (2x, 3×, etc.)
        - Individual item prices
        - Tax amount (if shown separately)
        - Tip amount (if shown separately)
        - Merchant/restaurant name
        - Total amount
        
        IGNORE:
        - Order numbers, receipt numbers, check numbers
        - Dates, times, addresses, phone numbers
        - Payment method information
        - Cashier names, table numbers, server names
        - Promotional text, loyalty points, discounts
        - Any non-food/beverage items
        
        Return ONLY valid JSON in this exact format:
        {
          "merchant_name": "Restaurant Name",
          "items": [
            {
              "name": "Item Name",
              "price": 12.99,
              "quantity": 1
            }
          ],
          "tax": 2.50,
          "tip": 5.00,
          "total": 25.98
        }
        
        If tax or tip are not shown separately, set them to 0. The tax and tip will be split evenly among all participants.
        """
        
        let userPrompt = "Analyze this receipt image and extract only the food/beverage items with their prices:"
        
        let requestBody: [String: Any] = [
            "model": "gpt-4o-mini", // Vision-capable model
            "messages": [
                ["role": "system", "content": systemPrompt],
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "text",
                            "text": userPrompt
                        ],
                        [
                            "type": "image_url",
                            "image_url": [
                                "url": "data:image/jpeg;base64,\(base64Image)"
                            ]
                        ]
                    ]
                ]
            ],
            "temperature": 0.1, // Low temperature for consistent parsing
            "max_tokens": 1000
        ]
        
        guard let url = URL(string: openAIURL) else {
            throw OCRError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30.0
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            throw OCRError.requestFailed("Failed to create OpenAI request: \(error.localizedDescription)")
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OCRError.requestFailed("Invalid response from OpenAI")
        }
        
        print("🤖 OpenAI API response: \(httpResponse.statusCode)")
        
        guard httpResponse.statusCode == 200 else {
            if let responseString = String(data: data, encoding: .utf8) {
                print("❌ OpenAI Error Response: \(responseString)")
            }
            throw OCRError.apiError(httpResponse.statusCode, "OpenAI API error")
        }
        
        // Parse OpenAI response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw OCRError.parsingFailed("Invalid OpenAI response structure")
        }
        
        print("🤖 AI Response: \(content)")
        
        // Parse the JSON response from AI
        return try parseAIResponse(content, originalImage: base64Image)
    }
    
    private func parseAIResponse(_ jsonString: String, originalImage: String) throws -> OCRResult {
        // Clean up the JSON string (remove markdown formatting if present)
        let cleanedJSON = jsonString
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let jsonData = cleanedJSON.data(using: .utf8) else {
            throw OCRError.parsingFailed("Failed to convert AI response to data")
        }
        
        struct AIReceiptResponse: Codable {
            let merchant_name: String?
            let items: [AIItem]
            let tax: Double?
            let tip: Double?
            let total: Double?
        }
        
        struct AIItem: Codable {
            let name: String
            let price: Double
            let quantity: Int?
        }
        
        let aiResponse = try JSONDecoder().decode(AIReceiptResponse.self, from: jsonData)
        
        // Convert AI response to our OCRResult format
        let receiptItems = aiResponse.items.map { aiItem in
            ReceiptItem(
                name: aiItem.name,
                originalName: aiItem.name,
                price: Decimal(aiItem.price),
                quantity: aiItem.quantity ?? 1
            )
        }
        
        return OCRResult(
            fullText: "Receipt processed with OpenAI Vision",
            detectedLanguage: "en", // OpenAI processes in English
            items: receiptItems,
            totalAmount: aiResponse.total.map { Decimal($0) },
            merchantName: aiResponse.merchant_name,
            date: Date(), // Current date as fallback
            tax: aiResponse.tax.map { Decimal($0) } ?? Decimal.zero,
            tip: aiResponse.tip.map { Decimal($0) } ?? Decimal.zero
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