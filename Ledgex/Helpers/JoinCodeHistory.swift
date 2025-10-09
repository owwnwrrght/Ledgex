import Foundation

/// Tracks recently used group codes so joining again is faster.
@MainActor
final class JoinCodeHistory {
    static let shared = JoinCodeHistory()
    private let defaults = UserDefaults.standard
    private let storageKey = "JoinCodeHistory.recentCodes"
    private let maxStoredCodes = 5

    private init() {}

    func add(code: String) {
        var codes = recentCodes()
        let normalized = code.uppercased()

        // Move existing entry to the front if needed
        codes.removeAll { $0.caseInsensitiveCompare(normalized) == .orderedSame }
        codes.insert(normalized, at: 0)

        if codes.count > maxStoredCodes {
            codes = Array(codes.prefix(maxStoredCodes))
        }

        defaults.set(codes, forKey: storageKey)
    }

    func recentCodes() -> [String] {
        defaults.stringArray(forKey: storageKey) ?? []
    }

    func clear() {
        defaults.removeObject(forKey: storageKey)
    }
}
