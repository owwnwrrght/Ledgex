import Foundation

class APIKeyManager {
    static let shared = APIKeyManager()
    private let config: NSDictionary
    
    private init() {
        guard let path = Bundle.main.path(forResource: "Secrets", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path) else {
            fatalError("Secrets.plist not found or unreadable")
        }
        config = dict
    }
    
    private func string(for key: String) -> String? {
        guard let value = config[key] as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    
    var openAIKey: String {
        guard let key = string(for: "OPENAI_API_KEY") else {
            fatalError("Missing OPENAI_API_KEY in Secrets.plist")
        }
        return key
    }
    
    var tripInviteFunctionURL: URL? {
        guard let urlString = string(for: "TRIP_INVITE_FUNCTION_URL"),
              urlString.contains("http") else {
            return nil
        }
        return URL(string: urlString)
    }
}
