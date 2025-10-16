import Foundation

enum APIKeyError: LocalizedError {
    case secretsFileMissing
    case keyMissing(String)
    
    var errorDescription: String? {
        switch self {
        case .secretsFileMissing:
            return "Secrets.plist is missing from the app bundle."
        case .keyMissing(let key):
            return "Missing value for \(key) in Secrets.plist."
        }
    }
}

class APIKeyManager {
    static let shared = APIKeyManager()
    private let config: NSDictionary?
    
    private init() {
        if let path = Bundle.main.path(forResource: "Secrets", ofType: "plist"),
           let dict = NSDictionary(contentsOfFile: path) {
            config = dict
        } else {
            config = nil
            assertionFailure("Secrets.plist not found or unreadable. Falling back to safe defaults.")
            print("⚠️ [APIKeyManager] Secrets.plist not found or unreadable. Sensitive features will be disabled.")
        }
    }
    
    private func string(for key: String) -> String? {
        guard let config,
              let value = config[key] as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    
    func openAIKey() throws -> String {
        guard config != nil else {
            throw APIKeyError.secretsFileMissing
        }
        guard let key = string(for: "OPENAI_API_KEY") else {
            throw APIKeyError.keyMissing("OPENAI_API_KEY")
        }
        return key
    }
    
    var tripInviteFunctionURL: URL? {
        guard let urlString = string(for: "TRIP_INVITE_FUNCTION_URL"),
              let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        return url
    }
}
