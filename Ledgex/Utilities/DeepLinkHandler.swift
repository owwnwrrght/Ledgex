import Foundation

enum DeepLink {
    case joinTrip(code: String)
}

struct DeepLinkHandler {
    static func parse(url: URL) -> DeepLink? {
        print("🔗 DeepLinkHandler: Parsing URL: \(url.absoluteString)")
        print("   Scheme: \(url.scheme ?? "nil"), Host: \(url.host ?? "nil"), Path: \(url.path)")

        if let nestedLink = extractNestedLink(from: url) {
            print("🔗 Found nested link: \(nestedLink.absoluteString)")
            return parse(url: nestedLink)
        }

        let result: DeepLink?
        switch url.scheme?.lowercased() {
        case "ledgex":
            result = parseLedgexScheme(url)
        case "https", "http":
            result = parseUniversalLink(url)
        default:
            result = nil
        }

        if let result = result {
            print("✅ Successfully parsed deep link: \(result)")
        } else {
            print("❌ Failed to parse deep link")
        }

        return result
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
                // Try path-based format first: /join/ABC123
                let pathComponents = url.pathComponents.filter { $0 != "/" }
                if pathComponents.count >= 2,
                   pathComponents[0].lowercased() == "join",
                   pathComponents[1].count == Trip.codeLength {
                    return .joinTrip(code: pathComponents[1].uppercased())
                }

                // Fall back to query parameter format: /join?code=ABC123
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
