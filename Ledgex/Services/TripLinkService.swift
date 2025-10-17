import Foundation

actor TripLinkService {
    static let shared = TripLinkService()
    
    private var cachedLinks: [UUID: URL] = [:]
    private let session: URLSession
    private let functionURL: URL?
    private static let fallbackDomain = URL(string: "https://splyt-4801c.web.app/join")!
    private static let configuredFunctionURL: URL? = {
        guard
            let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
            let data = try? Data(contentsOf: url),
            let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
            let urlString = plist["TRIP_INVITE_FUNCTION_URL"] as? String,
            !urlString.isEmpty
        else {
            return nil
        }
        return URL(string: urlString)
    }()
    
    init(session: URLSession = .shared, functionURL: URL? = nil) {
        self.session = session
        self.functionURL = functionURL ?? Self.configuredFunctionURL
    }
    
    func link(for trip: Trip) async -> URL {
        if let cached = cachedLinks[trip.id] {
            return cached
        }
        
        if let functionURL {
            do {
                let url = try await requestDynamicLink(for: trip, endpoint: functionURL)
                cachedLinks[trip.id] = url
                return url
            } catch {
                print("⚠️ Falling back to static trip link: \(error)")
            }
        }
        let fallbackURL = fallbackLink(for: trip)
        cachedLinks[trip.id] = fallbackURL
        return fallbackURL
    }
    
    private func requestDynamicLink(for trip: Trip, endpoint: URL) async throws -> URL {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "groupCode": trip.code,
            "groupName": trip.name,
            "tripCode": trip.code,
            "tripName": trip.name
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        guard (200..<300).contains(httpResponse.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(
                domain: "TripLinkService",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: errorText]
            )
        }
        
        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let linkString = json["shortLink"] as? String,
           let url = URL(string: linkString) {
            return url
        }
        
        throw URLError(.cannotParseResponse)
    }
    
    private func fallbackLink(for trip: Trip) -> URL {
        TripLinkService.fallbackLink(for: trip)
    }
    
    static func fallbackLink(for trip: Trip) -> URL {
        var components = URLComponents(url: fallbackDomain, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "type", value: "group"),
            URLQueryItem(name: "code", value: trip.code)
        ]
        return components.url ?? fallbackDomain
    }
}
