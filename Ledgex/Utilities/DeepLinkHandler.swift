import Foundation

enum DeepLink {
    case joinTrip(code: String)
}

struct DeepLinkHandler {
    static func parse(url: URL) -> DeepLink? {
        if let nestedLink = extractNestedLink(from: url) {
            return parse(url: nestedLink)
        }
        
        switch url.scheme?.lowercased() {
        case "ledgex":
            return parseLedgexScheme(url)
        case "https", "http":
            return parseUniversalLink(url)
        default:
            return nil
        }
    }
    
    private static func parseLedgexScheme(_ url: URL) -> DeepLink? {
        guard url.host?.lowercased() == "join" else { return nil }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let code = components?.queryItems?.first(where: { $0.name == "code" })?.value
        guard let code, code.count == Trip.codeLength else { return nil }
        return .joinTrip(code: code.uppercased())
    }
    
    private static func parseUniversalLink(_ url: URL) -> DeepLink? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        
        let host = components.host?.lowercased()

        if host == "ledgex.app" || host == "splyt.app" || host == "splyt-4801c.web.app" || host == "splyt-4801c.firebaseapp.com" {
            if url.path.lowercased().contains("join") {
                if let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
                   code.count == Trip.codeLength {
                    return .joinTrip(code: code.uppercased())
                }
            }
        }

        if host == "ledgex.page.link" || host == "splyt.page.link" {
            if let linkParam = components.queryItems?.first(where: { $0.name == "link" })?.value,
               let nestedURL = URL(string: linkParam) {
                return parse(url: nestedURL)
            }
        }
        
        return nil
    }
    
    private static func extractNestedLink(from url: URL) -> URL? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        if let deepLink = components.queryItems?.first(where: { $0.name == "link" })?.value,
           let nestedURL = URL(string: deepLink) {
            return nestedURL
        }
        return nil
    }
}
